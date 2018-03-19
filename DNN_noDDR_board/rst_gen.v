//-----------------------------------------------------------------------------
//  
//  Copyright (c) 2009 Xilinx Inc.
//
//  Project  : Programmable Wave Generator
//  Module   : rst_gen.v
//  Parent   : wave_gen.v
//  Children : reset_bridge.v
//
//  Description: 
//     This module is the reset generator for the design.
//     It takes the asynchronous reset in (from the IBUF), and generates
//     three synchronous resets - one on each clock domain.
//
//  Parameters:
//     None
//
//  Notes       : 
//
//  Multicycle and False Paths
//     None

`timescale 1ns/1ps


module rst_gen (
  input             clk_i,          // Receive clock
  input             rst_i,           // Asynchronous input - from IBUF
  output            rst_o      // Reset, synchronized to clk_sys
);
  // Instantiate the reset bridges

  // For clk_rx
  reset_bridge reset_bridge_clk_i0 (
    .clk_dst   (clk_i),
    .rst_in    (rst_i),
    .rst_dst   (rst_o)
  );

endmodule
