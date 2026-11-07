// Bounded end-to-end proof: arbitrary user traffic, initial physical RAM,
// and one symbolic faulty main row. Includes a completed test and retest.
module user_port(
 input wire clk,
 input wire user_en,user_we,
 input wire user_addr,
 input wire [1:0] user_wdata
);
parameter READ_LATENCY=0, RESET_RETEST=0;
localparam AW=1,DW=2,SPARES=1,DEPTH=2;
localparam TEST_CYCLES=(10+5*READ_LATENCY)*5;
localparam RETEST=TEST_CYCLES+12;
localparam LAST_CYCLE=RETEST+TEST_CYCLES+12;
reg [8:0] cycle=0;
always @(posedge clk) if(cycle<LAST_CYCLE) cycle<=cycle+1'b1;
wire rst_n=(cycle!=0) && !(RESET_RETEST && cycle==RETEST-1);
wire start=(cycle==1 || cycle==RETEST);
wire busy,done,fault_found,unrepairable,repair_pass,user_ready,user_rvalid,mem_en,mem_we;
wire [1:0] fail_count,first_fail_addr,mem_addr,first_fail_mask,mem_wdata,mem_rdata,user_rdata;
wire spare_bad;
(* anyconst *) reg fault_address;
(* anyconst *) reg [1:0] fault_mask;
(* anyconst *) reg stuck_value;
always @* assume(fault_mask!=0);
reg [1:0] physical[0:2],registered_data;
wire [1:0] raw_data=(mem_addr=={1'b0,fault_address}) ?
 (stuck_value ? (physical[mem_addr] | fault_mask) : (physical[mem_addr] & ~fault_mask)) : physical[mem_addr];
assign mem_rdata=READ_LATENCY ? registered_data : raw_data;
always @(posedge clk) begin
 if(mem_en && mem_we) physical[mem_addr]<=mem_wdata;
 if(mem_en && !mem_we) registered_data<=raw_data;
end
mbist_subsystem #(.AW(AW),.DW(DW),.SPARES(SPARES),.READ_LATENCY(READ_LATENCY)) dut(.*);
// Independent logical memory model: successful MBIST initializes every word to 0.
reg [1:0] logical_memory[0:1];
reg expected_valid;
reg [1:0] expected_data;
always @(posedge clk) begin
 if(!rst_n || start) begin
   logical_memory[0]<=0; logical_memory[1]<=0; expected_valid<=0;
 end else begin
   if(user_ready && user_en && user_we) logical_memory[user_addr]<=user_wdata;
   expected_valid<=user_ready && user_en && !user_we;
   if(user_ready && user_en && !user_we) expected_data<=logical_memory[user_addr];
 end
end
always @(posedge clk) if(cycle>0) begin
 assert(!mem_we || mem_en);
 if(mem_en) assert(mem_addr<3);
 assert(!user_ready || (done && repair_pass && !busy && rst_n && !start));
 if(!rst_n) assert(!mem_en && !mem_we && !user_ready && !user_rvalid);
 if(start || busy) assert(!user_ready && !user_rvalid);
 if(!busy && !user_ready) assert(!mem_en);
 if(user_ready) begin
   assert(mem_en==user_en);
   assert(mem_we==(user_en && user_we));
   assert(mem_addr!= {1'b0,fault_address});
   assert(mem_addr==(user_addr==fault_address ? 2 : {1'b0,user_addr}));
 end
 if(READ_LATENCY) begin
   assert(user_rvalid==(user_ready && expected_valid));
   if(user_rvalid) assert(user_rdata==expected_data);
 end else begin
   assert(user_rvalid==(user_ready && user_en && !user_we));
   if(user_rvalid) assert(user_rdata==logical_memory[user_addr]);
 end
 if(!user_rvalid) assert(user_rdata==0);
 // Require completed, reachable normal-access windows before and after retest.
 if((cycle>=TEST_CYCLES+2 && cycle<RETEST-1) || cycle>=RETEST+TEST_CYCLES+1)
   assert(done && repair_pass && !busy && !unrepairable);
end
endmodule
