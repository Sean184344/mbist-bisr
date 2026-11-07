// March C-: up(w0), up(r0,w1), up(r1,w0), down(r0,w1),
// down(r1,w0), up(r0). External memory: synchronous writes,
// READ_LATENCY=0: combinational reads; =1: one-cycle registered reads. Each logical word is a repairable row.
`timescale 1ns/1ps
module mbist_bisr #(
 parameter AW=4, DW=8, SPARES=2, READ_LATENCY=0
)(
 input wire clk, rst_n, start,
 output reg busy, done, fault_found, unrepairable,
 output reg [AW:0] fail_count,
 output reg [AW:0] first_fail_addr,
 output reg repair_pass,
 output reg [SPARES-1:0] spare_bad,
 output reg [DW-1:0] first_fail_mask,
 input wire [AW-1:0] user_addr,
 output reg [AW:0] mapped_addr,
 output reg mem_en, mem_we,
 output reg [AW:0] mem_addr,
 output reg [DW-1:0] mem_wdata,
 input wire [DW-1:0] mem_rdata
);
 localparam DEPTH=(1<<AW);
 localparam SLOT_W=(SPARES>1) ? $clog2(SPARES) : 1;
 reg [2:0] phase;
 reg write_step;
 reg read_pending;
 reg [AW:0] addr;
 reg [1:0] mode; // 0: qualify spares, 1: diagnose raw memory, 2: verify mapping
 reg [AW:0] last_addr;
 reg [SPARES-1:0] valid;
 reg [AW-1:0] bad_row [0:SPARES-1];
 integer i, match_slot, free_slot;
 reg expected;
 wire mismatch = mem_rdata != {DW{expected}};
 always @* begin
   mapped_addr={1'b0,user_addr};
   for (integer j=0;j<SPARES;j=j+1)
     if(valid[j] && bad_row[j]==user_addr) mapped_addr=(AW+1)'(DEPTH+j);
   mem_en=busy && !read_pending;
   last_addr=(mode==0) ? (AW+1)'(SPARES-1) : (AW+1)'(DEPTH-1);
   mem_addr=(mode==0) ? (AW+1)'(DEPTH)+addr : addr;
   if(mode==2)
     for(integer m=0;m<SPARES;m=m+1)
       if(valid[m] && {1'b0,bad_row[m]}==addr) mem_addr=(AW+1)'(DEPTH+m);
   mem_we=busy && (phase==0 || (phase!=5 && write_step));
   expected=(phase==2 || phase==4);
   mem_wdata={DW{(phase==1 || phase==3)}};
   match_slot=-1; free_slot=-1;
   for(integer k=0;k<SPARES;k=k+1) begin
     if(valid[k] && {1'b0,bad_row[k]}==addr) match_slot=k;
     if(!valid[k] && !spare_bad[k] && free_slot==-1) free_slot=k;
   end
 end
 always @(posedge clk) begin
   if(!rst_n) begin
     busy<=0; done<=0; fault_found<=0; unrepairable<=0;
     fail_count<=0; first_fail_addr<=0; first_fail_mask<=0;
     phase<=0; addr<=0; write_step<=0; valid<=0;
     mode<=0; spare_bad<=0; repair_pass<=0; read_pending<=0;
     for(i=0;i<SPARES;i=i+1) bad_row[i]<=0;
   end else if(!busy) begin
     if(start) begin
       busy<=1; done<=0; fault_found<=0; unrepairable<=0;
       fail_count<=0; first_fail_addr<=0; first_fail_mask<=0;
       phase<=0; addr<=0; write_step<=0; valid<=0;
       mode<=0; spare_bad<=0; repair_pass<=0; read_pending<=0;
     end
   end else if(READ_LATENCY==1 && !mem_we && !read_pending) begin
     // Issue read at this edge; consume registered RAM data at the next edge.
     read_pending<=1;
   end else begin
     read_pending<=0;
     if(!mem_we && mismatch) begin
       fault_found<=1;
       if(!fault_found) begin
         first_fail_addr<=mem_addr;
         first_fail_mask<=mem_rdata ^ {DW{expected}};
       end
       // Count failing reads, saturating at maximum counter value.
       if(!(&fail_count)) fail_count<=fail_count+1'b1;
       if(mode==0) spare_bad[addr[SLOT_W-1:0]]<=1;
       else if(mode==2) unrepairable<=1;
       else if(match_slot==-1) begin
         if(free_slot!=-1) begin valid[free_slot]<=1; bad_row[free_slot]<=addr[AW-1:0]; end
         else unrepairable<=1;
       end
     end
     if(phase!=0 && phase!=5 && !write_step) write_step<=1;
     else begin
       write_step<=0;
       if(((phase==3 || phase==4) && addr==0) ||
          ((phase!=3 && phase!=4) && addr==last_addr)) begin
         if(phase==5) begin
           if(mode==2) begin
             busy<=0; done<=1;
             repair_pass<=!unrepairable && !mismatch;
           end else begin mode<=mode+1'b1; phase<=0; addr<=0; end
         end
         else begin
           phase<=phase+1'b1;
           if(phase==2 || phase==3) addr<=last_addr; else addr<=0;
         end
       end else if(phase==3 || phase==4) addr<=addr-1'b1;
       else addr<=addr+1'b1;
     end
   end
 end
endmodule
