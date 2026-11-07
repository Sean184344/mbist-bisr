`timescale 1ns/1ps
// Portable reference RAM. Vendor-specific block RAM inference is tool dependent.
// Match READ_LATENCY and geometry to the connected mbist_subsystem.
module mbist_ram #(
 parameter AW=4, DW=8, SPARES=2, READ_LATENCY=1
)(
 input wire clk, mem_en, mem_we,
 input wire [AW:0] mem_addr,
 input wire [DW-1:0] mem_wdata,
 output wire [DW-1:0] mem_rdata
);
 reg [DW-1:0] storage [0:(1<<AW)+SPARES-1];
 always @(posedge clk)
   if(mem_en && mem_we) storage[mem_addr]<=mem_wdata;
 generate if(READ_LATENCY==0) begin: asynchronous_read
   assign mem_rdata=storage[mem_addr];
 end else begin: synchronous_read
   reg [DW-1:0] read_data;
   always @(posedge clk)
     if(mem_en && !mem_we) read_data<=storage[mem_addr];
   assign mem_rdata=read_data;
 end endgenerate
endmodule
