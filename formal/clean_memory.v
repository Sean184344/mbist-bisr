// Small-instance bounded proof: arbitrary initial RAM contents, deterministic
// reset/start, optional single faulty row with symbolic location/mask/polarity. This is not an unbounded or all-geometry proof.
module clean_memory(input wire clk);
parameter READ_LATENCY=0, INJECT_FAULT=0;
localparam AW=1,DW=2,SPARES=1,DEPTH=2;
localparam TEST_CYCLES=(10+5*READ_LATENCY)*(2*DEPTH+SPARES);
reg [7:0] cycle=0;
always @(posedge clk) if(cycle<TEST_CYCLES+5) cycle<=cycle+1'b1;
wire rst_n=(cycle!=0);
wire start=(cycle==1);
wire busy,done,fault_found,unrepairable,repair_pass,mem_en,mem_we;
wire [AW:0] fail_count,first_fail_addr,mem_addr,mapped_addr;
wire [DW-1:0] first_fail_mask,mem_wdata,mem_rdata;
wire [SPARES-1:0] spare_bad;
(* anyconst *) reg [AW-1:0] fault_address;
(* anyconst *) reg [DW-1:0] fault_mask;
(* anyconst *) reg stuck_value;
always @* if(INJECT_FAULT) assume(fault_mask!=0);
wire [AW-1:0] user_addr=INJECT_FAULT ? fault_address : 0;
reg [DW-1:0] memory[0:DEPTH+SPARES-1];
reg [DW-1:0] registered_data;
wire [DW-1:0] physical_data=(INJECT_FAULT && mem_addr=={1'b0,fault_address}) ?
  (stuck_value ? (memory[mem_addr] | fault_mask) : (memory[mem_addr] & ~fault_mask)) : memory[mem_addr];
assign mem_rdata=READ_LATENCY ? registered_data : physical_data;
always @(posedge clk) begin
 if(mem_en && mem_we) memory[mem_addr]<=mem_wdata;
 if(mem_en && !mem_we) registered_data<=physical_data;
end
mbist_bisr #(.AW(AW),.DW(DW),.SPARES(SPARES),.READ_LATENCY(READ_LATENCY)) dut(.*);
always @(posedge clk) if(cycle>0) begin
 assert(!(busy && done));
 assert(!repair_pass || (done && !busy && !unrepairable));
 if(mem_en) assert(mem_addr<DEPTH+SPARES);
 assert(!mem_we || mem_en);
 assert(!unrepairable && spare_bad==0);
 if(!INJECT_FAULT) assert(!fault_found && fail_count==0);
 if(cycle>=TEST_CYCLES+2) begin
   assert(done && repair_pass && !busy);
   assert(memory[0]==0 && memory[1]==0 && memory[2]==0);
   if(INJECT_FAULT) begin
     assert(fault_found && fail_count!=0);
     assert(first_fail_addr=={1'b0,fault_address} && first_fail_mask==fault_mask);
     assert(mapped_addr==DEPTH);
   end else assert(mapped_addr==0);
 end
end
endmodule
