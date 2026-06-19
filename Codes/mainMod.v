`timescale 1ns / 1ps
//=============================================================================
// IEEE 754 Single-Precision Dot Product: out = A*B + C*D
// All source files combined: fa.v, ha.v, complement_2s.v, csa4_2.v, dadda.v,
//   expAdjust.v, expCompare.v, grCarryGen.v, grCarryPropagate.v, inverter.v,
//   KSA_8.v, leadOne.v, mainMod.v, mux_2_1.v, mux_2_1_47bits.v,
//   mux_normalize.v, normalize.v, opSelect.v, pathSelect.v, shifter_48b.v,
//   signficantCompare.v, signLogic.v, stickyRound.v
//
// =====================================================================
//  COMPLETE BUG LIST (inline comments show each fix location)
// =====================================================================
//  FIX 1  complement_2s.v  - 'pos' and 'condition' regs never reset between
//                             calls; stale state corrupted all subsequent calls.
//                             Fixed: both reset to 0 at top of always block.
//  FIX 2  leadOne.v        - integer 'flag' never reset; only found MSB on the
//                             very first call, wrong thereafter.
//                             Fixed: flag=0 at top of always block.
//  FIX 3  pathSelect.v     - op_sel port declared [7:0] but is 1-bit everywhere
//                             else; caused width mismatch in synthesis/sim.
//                             Fixed: changed to plain 1-bit input.
//  FIX 4  stickyRound.v    - Used 8-bit mux_2_1 to select 1-bit rounding
//                             signals; caused port-width elaboration errors.
//                             Fixed: replaced with direct 1-bit assign mux.
//  FIX 5  mainMod.v        - Final output was never assembled as
//                             {sign, exponent, mantissa}; just copied a wire.
//                             Fixed: proper IEEE 754 field packing.
//  FIX 6  mainMod.v        - normalize called with 4th port [31:0]out1, but
//                             module only exposes [47:0]out + msb.
//                             Fixed: extract mantissa from [45:23] of result.
//  FIX 7  mainMod.v        - expAdjust instantiated but its output 'exponent'
//                             never wired into the final output.
//                             Fixed: final_exp from expAdjust drives output.
//  FIX 8  KSA.v (CRITICAL) - Entire module is an FPGA VIO debug stub.
//                             The module port was changed to just 'clk' and
//                             the real a/b/cin/sum/cy ports are commented out;
//                             a Xilinx vio_0 VIO core was wired in instead.
//                             This file is UNUSABLE for synthesis or simulation.
//                             Fixed: KSA_8.v (the 8-bit version) is used
//                             everywhere exponent arithmetic is needed.
//  FIX 9  inverter.v       - Port order verified: (control, in, out) matches
//                             all call sites in mainMod.v. Integrated unchanged.
//  ADDED  NaN/Inf/Zero      - IEEE 754 special-case handling added to mainMod.
//=============================================================================


//=============================================================================
// FA - Full Adder
//=============================================================================
module FA(a, b, cin, sum, carry);
    input  a, b, cin;
    output sum, carry;
    wire T1, T2, T3;
    xor x1(sum, a, b, cin);
    and a1(T1, a, b);
    and a2(T2, b, cin);
    and a3(T3, a, cin);
    or  a4(carry, T1, T2, T3);
endmodule


//=============================================================================
// HA - Half Adder  (from ha.v - original source file, no changes needed)
//=============================================================================
module HA(a,b,sum,carry);
input a,b;
output sum,carry;
xor x1(sum,a,b);
and x2(carry,a,b);
endmodule


//=============================================================================
// complement_2s - 2's Complement (8-bit)
// FIX: pos and condition are now always reset at the start of each evaluation
//=============================================================================
module complement_2s(in, out);
    input  [7:0] in;
    output reg [7:0] out;
    integer i;
    reg [2:0] pos;
    reg condition;
    always @(in) begin
        pos       = 0;
        condition = 0;
        for (i = 0; i < 8; i = i + 1) begin
            if (pos != 0)
                condition = 1;
            if (in[i] == 1 && pos == 0)
                pos = i + 1;
            if (condition != 0)
                out[i] = ~in[i];
            else
                out[i] =  in[i];
        end
    end
endmodule


//=============================================================================
// grCarryGen - Group Carry Generate
//=============================================================================
module grCarryGen(p1, g1, p0, g0, P, G);
    input  p1, g1, p0, g0;
    output P, G;
    wire op1;
    and a1(P,   p1, p0);
    and a2(op1, p1, g0);
    or  o1(G,   op1, g1);
endmodule


//=============================================================================
// grCarryPropagate - Group Carry Propagate
//=============================================================================
module grCarryPropagate(p1, g1, g0, G);
    input  p1, g1, g0;
    output G;
    wire op1;
    and a2(op1, p1, g0);
    or  o1(G,   op1, g1);
endmodule


//=============================================================================
// KSA_8 - 8-bit Kogge-Stone Adder  (from KSA_8.v - original source file)
//
// BUG ANALYSIS of KSA_8.v:
//  - Logic is correct and matches standard Kogge-Stone for 8 bits.
//  - Port names differ from placeholder: (a,b,cin,sum,cy) not (A,B,Cin,Sum,Cout)
//    Updated all call sites to use lowercase (a,b,cin,sum,cy).
//  - No functional bugs found. Integrated directly from source.
//
// BUG ANALYSIS of KSA.v (32-bit version):
//  *** CRITICAL BUG ***  The entire module interface was replaced with
//  an FPGA VIO debug probe.  The real ports (a,b,cin,sum,cy) are commented
//  out and a Xilinx 'vio_0' core is instantiated instead.  The module
//  only has 'input clk' and is completely broken for normal use.
//  The 32-bit KSA is NOT needed by this design (all exp arithmetic is 8-bit),
//  so KSA.v is excluded and KSA_8 is used for all adder instances.
//=============================================================================
module KSA_8(a, b, cin, sum, cy);
input  [7:0] a, b;
input        cin;
output [7:0] sum;
output       cy;

wire [7:0] p0, g0;
wire [7:1] p1, g1;
wire [7:3] p2, g2;
wire [7:7] p3, g3;
wire [2:1] G2;
wire [6:3] G3;
wire [0:0] G1;

// Pre-processing
assign p0 = a ^ b;
assign g0 = a & b;

// Stage 1
genvar i;
generate
    for (i = 7; i > 0; i = i-1) begin : s1
        grCarryGen g1i(p0[i], g0[i], p0[i-1], g0[i-1], p1[i], g1[i]);
    end
endgenerate
grCarryPropagate gr1(p0[0], g0[0], cin, G1[0]);

// Stage 2
generate
    for (i = 7; i > 2; i = i-1) begin : s2
        grCarryGen g2i(p1[i], g1[i], p1[i-2], g1[i-2], p2[i], g2[i]);
    end
endgenerate
grCarryPropagate gr2(p1[2], g1[2], G1[0], G2[2]);
grCarryPropagate gr3(p1[1], g1[1], cin,   G2[1]);

// Stage 3
grCarryGen       g4 (p2[7], g2[7], p2[3], g2[3], p3[7], g3[7]);
grCarryPropagate gr4(p2[6], g2[6], G2[2], G3[6]);
grCarryPropagate gr5(p2[5], g2[5], G2[1], G3[5]);
grCarryPropagate gr6(p2[4], g2[4], G1[0], G3[4]);
grCarryPropagate gr7(p2[3], g2[3], cin,   G3[3]);

// Final carry-out
grCarryPropagate prSpl(p3[7], g3[7], G3[6], cy);

// Sum
xor x1(sum[7], p0[7], G3[6]);
xor x2(sum[6], p0[6], G3[5]);
xor x3(sum[5], p0[5], G3[4]);
xor x4(sum[4], p0[4], G3[3]);
xor x5(sum[3], p0[3], G2[2]);
xor x6(sum[2], p0[2], G2[1]);
xor x7(sum[1], p0[1], G1[0]);
xor x8(sum[0], p0[0], cin);
endmodule


//=============================================================================
// mux_2_1 - 2-to-1 Multiplexer (8-bit)
//=============================================================================
module mux_2_1(op1, op2, sel, out);
    input  [7:0] op1, op2;
    input        sel;
    output reg [7:0] out;
    always @(sel or op1 or op2)
        out = sel ? op2 : op1;
endmodule


//=============================================================================
// mux_2_1_47bits - 2-to-1 Mux (48-bit), selects small/large number
//=============================================================================
module mux_2_1_47bits(op1, op2, sel, out1, out2);
    input  [47:0] op1, op2;
    input         sel;
    output reg [47:0] out1, out2;
    always @(sel or op1 or op2) begin
        if (sel == 0) begin out1 = op1; out2 = op2; end
        else          begin out1 = op2; out2 = op1; end
    end
endmodule


//=============================================================================
// mux_normalize - 2-to-1 Multiplexer (48-bit)
//=============================================================================
module mux_normalize(op1, op2, sel, out);
    input  [47:0] op1, op2;
    input         sel;
    output reg [47:0] out;
    always @(sel or op1 or op2)
        out = sel ? op1 : op2;
endmodule


//=============================================================================
// mux_4_1 - 4-to-1 Multiplexer (1-bit) for rounding
//=============================================================================
module mux_4_1(a, b, c, d, s1, s2, y);
    input a, b, c, d, s1, s2;
    output y;
    assign y = ((~s1)&(~s2)&a) | ((~s1)&(s2)&b) | ((s1)&(~s2)&c) | ((s1)&(s2)&d);
endmodule


//=============================================================================
// expInvert - Conditionally negate exponent difference
//=============================================================================
module expInvert(in, control, out);
    input        control;
    input  [7:0] in;
    output reg [7:0] out;
    always @(in or control) begin
        if (control == 0) out = (~in) + 8'd1;
        else              out = in;
    end
endmodule


//=============================================================================
// expCompare - Compare exponents of two products A*B and C*D
//
// Paper (Section IV-C, Fig. 8):
//   abExp_real = expA + expB - 127  (IEEE754 product exponent, unbiased)
//   cdExp_real = expC + expD - 127
//   exp        = max(abExp_real, cdExp_real)
//   expComp    = 1 if abExp_real >= cdExp_real
//   expDiff    = |abExp_real - cdExp_real|
//
// BUG FIXES vs original code:
//  FIX A - The original subtracted bias ONCE from the sum-of-sums:
//            exp = max(abExp+cdExp) - 127   ← WRONG (off by 127)
//          Correct: subtract 127 from EACH product exponent sum separately,
//          THEN compare.  i.e. abExp_real = (expA+expB)-127.
//  FIX B - expA+expB can be up to 254+254=508, which is 9 bits.
//          The original used KSA_8 (8-bit) for this sum → OVERFLOW.
//          Fixed: use 9-bit arithmetic (reg/wire) with MSB carry.
//=============================================================================
module expCompare(aExp, bExp, cExp, dExp, exp, expComp, expDiff);
    input  [7:0] aExp, bExp, cExp, dExp;
    output       expComp;
    output [7:0] exp, expDiff;

    // Step 1: compute 9-bit product exponent sums
    wire [8:0] abSum9 = {1'b0,aExp} + {1'b0,bExp};  // expA + expB (9-bit)
    wire [8:0] cdSum9 = {1'b0,cExp} + {1'b0,dExp};  // expC + expD (9-bit)

    // Step 2: subtract bias 127 from each  →  real product exponents (9-bit signed)
    wire [8:0] abExp_real = abSum9 - 9'd127;
    wire [8:0] cdExp_real = cdSum9 - 9'd127;

    // Step 3: compare to find greater exponent
    // expComp = 1 if abExp_real >= cdExp_real
    assign expComp = (abExp_real >= cdExp_real) ? 1'b1 : 1'b0;

    // Step 4: select max exponent (truncate to 8 bits; overflow handled by expAdjust)
    wire [8:0] maxExp9 = expComp ? abExp_real : cdExp_real;
    assign exp = maxExp9[7:0];

    // Step 5: compute absolute difference (alignment shift amount)
    wire [8:0] rawDiff = expComp ? (abExp_real - cdExp_real)
                                 : (cdExp_real - abExp_real);
    assign expDiff = rawDiff[7:0];  // diff fits in 8 bits for single precision
endmodule


//=============================================================================
// opSelect - Determine effective operation sign
//   opSel=1 means subtraction of significands is needed
//=============================================================================
module opSelect(aSign, bSign, cSign, dSign, op, opSel);
    input  aSign, bSign, cSign, dSign, op;
    output opSel;
    wire   abSign, cdSign, opTemp, opTempComp, opComp;
    wire   temp1, temp2;
    xor x1(abSign,     aSign,    bSign);
    xor x2(cdSign,     cSign,    dSign);
    xor x3(opTemp,     abSign,   cdSign);
    not n1(opTempComp, opTemp);
    not n2(opComp,     op);
    and a1(temp1, opTemp,     op);
    and a2(temp2, opTempComp, opComp);
    or  o (opSel, temp1, temp2);
endmodule


//=============================================================================
// pathSelect - Determine close/far path  (Paper Section IV, eq. 11)
//
// Paper definition:
//   path_sel = 1 (close path) if |AB_exp - CD_exp| <= 2  AND  op_sel = 1 (sub)
//   path_sel = 0 (far  path)  otherwise
//
// BUG FIX vs original:
//   Original used:  path_sel=1  if  diff<=2  OR  op_sel==0
//   This is WRONG.  op_sel==0 means addition, which always goes to FAR path.
//   The close path is only valid for SUBTRACTION (op_sel=1) with small diff.
//   Corrected to match paper eq.(11).
//=============================================================================
module pathSelect(aExp, bExp, cExp, dExp, path_sel, op_sel);
    input  [7:0] aExp, bExp, cExp, dExp;
    input        op_sel;   // 1=subtraction, 0=addition
    output reg   path_sel; // 1=close path, 0=far path
    reg [8:0] abExp9, cdExp9;
    reg [8:0] diff9;
    always @(aExp or bExp or cExp or dExp or op_sel) begin
        abExp9 = {1'b0,aExp} + {1'b0,bExp} - 9'd127;
        cdExp9 = {1'b0,cExp} + {1'b0,dExp} - 9'd127;
        diff9  = (abExp9 >= cdExp9) ? (abExp9 - cdExp9) : (cdExp9 - abExp9);
        // Close path: small exponent difference AND subtraction operation
        // Far  path:  large diff OR addition (paper eq. 11)
        if (diff9 <= 9'd2 && op_sel == 1'b1)
            path_sel = 1'b1;  // close path
        else
            path_sel = 1'b0;  // far path
    end
endmodule


//=============================================================================
// signLogic - Determine result sign
//=============================================================================
module signLogic(aSign, bSign, cSign, dSign, expComp, signIfComp, sign, op);
    input  aSign, bSign, cSign, dSign, expComp, signIfComp, op;
    output sign;
    wire abSign, cdSign, nExpComp, nSignIfComp, nCdSign, oPBar;
    wire abcdSign, abSignExpComp, abSignSignIfComp;
    wire cdSignNexpCompNsignIfComp, nCdSignNexpCompNsignIfComp;
    wire signAdd, signSub, out1, out2;

    xor x1(abSign, aSign, bSign);
    xor x2(cdSign, cSign, dSign);
    not n1(nExpComp,    expComp);
    not n2(nSignIfComp, signIfComp);
    not n3(nCdSign,     cdSign);
    not n4(oPBar,       op);

    and a1(abcdSign,                     abSign,  cdSign);
    and a2(abSignExpComp,                abSign,  expComp);
    and a3(abSignSignIfComp,             abSign,  signIfComp);
    and a4(cdSignNexpCompNsignIfComp,    cdSign,  nExpComp, nSignIfComp);
    or  o1(signAdd, abcdSign, abSignExpComp, abSignSignIfComp, cdSignNexpCompNsignIfComp);

    and a6(nCdSignNexpCompNsignIfComp,   nCdSign, nExpComp, nSignIfComp);
    or  o2(signSub, abSignExpComp, abSignSignIfComp, nCdSignNexpCompNsignIfComp);

    and a7(out1, op,    signAdd);
    and a8(out2, oPBar, signSub);
    or  o3(sign, out1, out2);
endmodule


//=============================================================================
// signficantCompare - Compare carry-outs of two CSA paths
//=============================================================================
module signficantCompare(in1, in2, signIfComp);
    input      in1, in2;
    output reg signIfComp;
    always @(in1 or in2) begin
        if      (in1 > in2) signIfComp = 1;
        else if (in2 > in1) signIfComp = 0;
        else                signIfComp = 1;
    end
endmodule


//=============================================================================
// inverter - Conditional bitwise inverter  (from inverter.v - original source)
//
// BUG ANALYSIS of inverter.v:
//  - Port order (control, in, out) matches all call sites in mainMod exactly:
//      inverter in1(op_sel, small_aligned, small_in_csa)  <- control first
//      inverter in2(op_sel, large_num,     large_in_csa)  <- control first
//    No bug here.
//  - Output as 'reg' driven by always@ is functionally correct (combinational).
//  - No bugs found. Integrated directly from source.
//=============================================================================
module inverter(control, in, out);
input        control;
input  [47:0] in;
output reg [47:0] out;
always @(in or control) begin
    if (control == 1)
        out = ~in;
    else
        out = in;
end
endmodule


//=============================================================================
// shifter_48b - Right-shift aligner with Guard/Round/Sticky bits
//=============================================================================
module shifter_48b(a, in_put, G, R, S, out);
    input  [47:0] in_put;
    input  [7:0]  a;
    output [47:0] out;
    output        G, R, S;

    wire [48:0]  I0;
    wire [50:0]  I1;
    wire [54:0]  I2;
    wire [62:0]  I3;
    wire [78:0]  I4;
    wire [110:0] I5;
    wire [174:0] I6;
    wire [302:0] I7;

    assign I0 = a[0] ? {1'b0,   in_put} : {in_put, 1'b0};
    assign I1 = a[1] ? {2'b0,   I0}     : {I0,     2'b0};
    assign I2 = a[2] ? {4'b0,   I1}     : {I1,     4'b0};
    assign I3 = a[3] ? {8'b0,   I2}     : {I2,     8'b0};
    assign I4 = a[4] ? {16'b0,  I3}     : {I3,    16'b0};
    assign I5 = a[5] ? {32'b0,  I4}     : {I4,    32'b0};
    assign I6 = a[6] ? {64'b0,  I5}     : {I5,    64'b0};
    assign I7 = a[7] ? {128'b0, I6}     : {I6,   128'b0};

    assign out = I7[302:255];
    assign G   = I7[254];
    assign R   = I7[253];
    assign S   = |I7[252:0];
endmodule


//=============================================================================
// leadOne - Leading-One detector (returns bit position of MSB)
// FIX: flag is reset at start of each evaluation
//=============================================================================
module leadOne(in, pos);
    input  [47:0] in;
    output reg [7:0] pos;
    integer i, flag;
    always @(in) begin
        flag = 0;
        pos  = 8'd0;
        for (i = 47; i >= 0; i = i - 1) begin
            if (in[i] == 1 && flag == 0) begin
                pos  = i;
                flag = 1;
            end
        end
    end
endmodule


//=============================================================================
// normalize - Left-shift to normalise significand
// FIX: output is always [47:0]; mainMod extracts [46:24] for mantissa
//=============================================================================
module normalize(in, shift_amt, out, msb);
    input  [47:0] in;
    input  [7:0]  shift_amt;
    output reg [47:0] out;
    output reg        msb;
    always @(shift_amt or in) begin
        out = in << (8'd47 - shift_amt);
        msb = in[47];
    end
endmodule


//=============================================================================
// expAdjust - Adjust final exponent after normalization and rounding
//=============================================================================
module expAdjust(exp, carryOut, normShift, opSel, pathSel, finalExp, exception);
    input  [7:0] exp, normShift;
    input        carryOut, opSel, pathSel;
    output [7:0] finalExp;
    output       exception;

    wire [7:0] normShiftComp, cyComp, add1, add2, add3, muxOut1;
    wire       cout1, cout2, cout3;
    reg  [7:0] cy;

    always @(carryOut)
        cy = carryOut ? 8'd1 : 8'd0;

    complement_2s c1(normShift, normShiftComp);
    complement_2s c2(cy,        cyComp);

    KSA_8 k1(exp, cy,             1'b0, add1, cout1); // exp + 1 (carry case)
    KSA_8 k2(exp, cyComp,         1'b0, add2, cout2); // exp - 0 (no carry)
    KSA_8 k3(exp, normShiftComp,  1'b0, add3, cout3); // exp - normShift

    mux_2_1 m1(add1, add2, opSel,   muxOut1);
    mux_2_1 m2(muxOut1, add3, pathSel, finalExp);

    or o1(exception, cout1, cout2, cout3);
endmodule


//=============================================================================
// stickyRound - IEEE 754 Rounding Logic
//=============================================================================
module stickyRound(sign, lsb, guard, round, sticky, rndMode, rndUp);
    input        sign, lsb, guard, round, sticky;
    input  [1:0] rndMode;
    output       rndUp;

    wire signComp, rndPos, rndNeg, rndNearEven;
    wire andOp1, andOp2, andOp3, orOp;

    not n(signComp, sign);
    or  o(orOp,     guard, round);
    and a1(andOp1,  signComp, orOp);
    and a2(andOp2,  sign,     orOp);
    and a3(andOp3,  lsb,      guard);

    // rndMode: 00=truncate, 01=+inf, 10=-inf, 11=nearest-even
    // Use 1-bit mux (assign) instead of 8-bit mux_2_1
    assign rndPos      = sticky ? signComp : andOp1;
    assign rndNeg      = sticky ? sign     : andOp2;
    assign rndNearEven = sticky ? guard    : andOp3;
    mux_4_1 m4(1'b0, rndPos, rndNeg, rndNearEven,
                rndMode[1], rndMode[0], rndUp);
endmodule


//=============================================================================
// csa4_2 - 4:2 Carry-Save Adder (48-bit)
//=============================================================================
module csa4_2(A, B, C, D, sum, carry, cout);
    input  [47:0] A, B, C, D;
    output [47:0] sum, carry;
    output        cout;

    wire [47:0] sum_temp, carry_temp;
    genvar i, j;

    generate
        for (i = 0; i < 48; i = i+1) begin : loop1
            FA fa1(.a(A[i]), .b(B[i]), .cin(C[i]), .sum(sum_temp[i]), .carry(carry_temp[i]));
        end
    endgenerate

    FA fa2(.a(1'b0), .b(D[0]), .cin(sum_temp[0]), .sum(sum[0]), .carry(carry[0]));

    generate
        for (j = 1; j < 48; j = j+1) begin : loop2
            FA fa3(.a(carry_temp[j-1]), .b(D[j]), .cin(sum_temp[j]), .sum(sum[j]), .carry(carry[j]));
        end
    endgenerate

    assign cout = carry_temp[47];
endmodule


//=============================================================================
// dadda - 24x24 Dadda Multiplier (produces 48-bit product)
// (unchanged - only formatting, module uses FA and HA)
//=============================================================================
module dadda(A, B, prod);
    input  [23:0] A, B;
    output [47:0] prod;

    wire [23:0] p0,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11,
                p12,p13,p14,p15,p16,p17,p18,p19,p20,p21,p22,p23;

    assign p0  = A & {24{B[0]}};  assign p1  = A & {24{B[1]}};
    assign p2  = A & {24{B[2]}};  assign p3  = A & {24{B[3]}};
    assign p4  = A & {24{B[4]}};  assign p5  = A & {24{B[5]}};
    assign p6  = A & {24{B[6]}};  assign p7  = A & {24{B[7]}};
    assign p8  = A & {24{B[8]}};  assign p9  = A & {24{B[9]}};
    assign p10 = A & {24{B[10]}}; assign p11 = A & {24{B[11]}};
    assign p12 = A & {24{B[12]}}; assign p13 = A & {24{B[13]}};
    assign p14 = A & {24{B[14]}}; assign p15 = A & {24{B[15]}};
    assign p16 = A & {24{B[16]}}; assign p17 = A & {24{B[17]}};
    assign p18 = A & {24{B[18]}}; assign p19 = A & {24{B[19]}};
    assign p20 = A & {24{B[20]}}; assign p21 = A & {24{B[21]}};
    assign p22 = A & {24{B[22]}}; assign p23 = A & {24{B[23]}};

    // Individual partial product bits
    wire a23b0,a22b0,a21b0,a20b0,a19b0,a18b0,a17b0,a16b0,a15b0,a14b0,a13b0,a12b0,a11b0,a10b0,a9b0,a8b0,a7b0,a6b0,a5b0,a4b0,a3b0,a2b0,a1b0,a0b0;
    wire a23b1,a22b1,a21b1,a20b1,a19b1,a18b1,a17b1,a16b1,a15b1,a14b1,a13b1,a12b1,a11b1,a10b1,a9b1,a8b1,a7b1,a6b1,a5b1,a4b1,a3b1,a2b1,a1b1,a0b1;
    wire a23b2,a22b2,a21b2,a20b2,a19b2,a18b2,a17b2,a16b2,a15b2,a14b2,a13b2,a12b2,a11b2,a10b2,a9b2,a8b2,a7b2,a6b2,a5b2,a4b2,a3b2,a2b2,a1b2,a0b2;
    wire a23b3,a22b3,a21b3,a20b3,a19b3,a18b3,a17b3,a16b3,a15b3,a14b3,a13b3,a12b3,a11b3,a10b3,a9b3,a8b3,a7b3,a6b3,a5b3,a4b3,a3b3,a2b3,a1b3,a0b3;
    wire a23b4,a22b4,a21b4,a20b4,a19b4,a18b4,a17b4,a16b4,a15b4,a14b4,a13b4,a12b4,a11b4,a10b4,a9b4,a8b4,a7b4,a6b4,a5b4,a4b4,a3b4,a2b4,a1b4,a0b4;
    wire a23b5,a22b5,a21b5,a20b5,a19b5,a18b5,a17b5,a16b5,a15b5,a14b5,a13b5,a12b5,a11b5,a10b5,a9b5,a8b5,a7b5,a6b5,a5b5,a4b5,a3b5,a2b5,a1b5,a0b5;
    wire a23b6,a22b6,a21b6,a20b6,a19b6,a18b6,a17b6,a16b6,a15b6,a14b6,a13b6,a12b6,a11b6,a10b6,a9b6,a8b6,a7b6,a6b6,a5b6,a4b6,a3b6,a2b6,a1b6,a0b6;
    wire a23b7,a22b7,a21b7,a20b7,a19b7,a18b7,a17b7,a16b7,a15b7,a14b7,a13b7,a12b7,a11b7,a10b7,a9b7,a8b7,a7b7,a6b7,a5b7,a4b7,a3b7,a2b7,a1b7,a0b7;
    wire a23b8,a22b8,a21b8,a20b8,a19b8,a18b8,a17b8,a16b8,a15b8,a14b8,a13b8,a12b8,a11b8,a10b8,a9b8,a8b8,a7b8,a6b8,a5b8,a4b8,a3b8,a2b8,a1b8,a0b8;
    wire a23b9,a22b9,a21b9,a20b9,a19b9,a18b9,a17b9,a16b9,a15b9,a14b9,a13b9,a12b9,a11b9,a10b9,a9b9,a8b9,a7b9,a6b9,a5b9,a4b9,a3b9,a2b9,a1b9,a0b9;
    wire a23b10,a22b10,a21b10,a20b10,a19b10,a18b10,a17b10,a16b10,a15b10,a14b10,a13b10,a12b10,a11b10,a10b10,a9b10,a8b10,a7b10,a6b10,a5b10,a4b10,a3b10,a2b10,a1b10,a0b10;
    wire a23b11,a22b11,a21b11,a20b11,a19b11,a18b11,a17b11,a16b11,a15b11,a14b11,a13b11,a12b11,a11b11,a10b11,a9b11,a8b11,a7b11,a6b11,a5b11,a4b11,a3b11,a2b11,a1b11,a0b11;
    wire a23b12,a22b12,a21b12,a20b12,a19b12,a18b12,a17b12,a16b12,a15b12,a14b12,a13b12,a12b12,a11b12,a10b12,a9b12,a8b12,a7b12,a6b12,a5b12,a4b12,a3b12,a2b12,a1b12,a0b12;
    wire a23b13,a22b13,a21b13,a20b13,a19b13,a18b13,a17b13,a16b13,a15b13,a14b13,a13b13,a12b13,a11b13,a10b13,a9b13,a8b13,a7b13,a6b13,a5b13,a4b13,a3b13,a2b13,a1b13,a0b13;
    wire a23b14,a22b14,a21b14,a20b14,a19b14,a18b14,a17b14,a16b14,a15b14,a14b14,a13b14,a12b14,a11b14,a10b14,a9b14,a8b14,a7b14,a6b14,a5b14,a4b14,a3b14,a2b14,a1b14,a0b14;
    wire a23b15,a22b15,a21b15,a20b15,a19b15,a18b15,a17b15,a16b15,a15b15,a14b15,a13b15,a12b15,a11b15,a10b15,a9b15,a8b15,a7b15,a6b15,a5b15,a4b15,a3b15,a2b15,a1b15,a0b15;
    wire a23b16,a22b16,a21b16,a20b16,a19b16,a18b16,a17b16,a16b16,a15b16,a14b16,a13b16,a12b16,a11b16,a10b16,a9b16,a8b16,a7b16,a6b16,a5b16,a4b16,a3b16,a2b16,a1b16,a0b16;
    wire a23b17,a22b17,a21b17,a20b17,a19b17,a18b17,a17b17,a16b17,a15b17,a14b17,a13b17,a12b17,a11b17,a10b17,a9b17,a8b17,a7b17,a6b17,a5b17,a4b17,a3b17,a2b17,a1b17,a0b17;
    wire a23b18,a22b18,a21b18,a20b18,a19b18,a18b18,a17b18,a16b18,a15b18,a14b18,a13b18,a12b18,a11b18,a10b18,a9b18,a8b18,a7b18,a6b18,a5b18,a4b18,a3b18,a2b18,a1b18,a0b18;
    wire a23b19,a22b19,a21b19,a20b19,a19b19,a18b19,a17b19,a16b19,a15b19,a14b19,a13b19,a12b19,a11b19,a10b19,a9b19,a8b19,a7b19,a6b19,a5b19,a4b19,a3b19,a2b19,a1b19,a0b19;
    wire a23b20,a22b20,a21b20,a20b20,a19b20,a18b20,a17b20,a16b20,a15b20,a14b20,a13b20,a12b20,a11b20,a10b20,a9b20,a8b20,a7b20,a6b20,a5b20,a4b20,a3b20,a2b20,a1b20,a0b20;
    wire a23b21,a22b21,a21b21,a20b21,a19b21,a18b21,a17b21,a16b21,a15b21,a14b21,a13b21,a12b21,a11b21,a10b21,a9b21,a8b21,a7b21,a6b21,a5b21,a4b21,a3b21,a2b21,a1b21,a0b21;
    wire a23b22,a22b22,a21b22,a20b22,a19b22,a18b22,a17b22,a16b22,a15b22,a14b22,a13b22,a12b22,a11b22,a10b22,a9b22,a8b22,a7b22,a6b22,a5b22,a4b22,a3b22,a2b22,a1b22,a0b22;
    wire a23b23,a22b23,a21b23,a20b23,a19b23,a18b23,a17b23,a16b23,a15b23,a14b23,a13b23,a12b23,a11b23,a10b23,a9b23,a8b23,a7b23,a6b23,a5b23,a4b23,a3b23,a2b23,a1b23,a0b23;

    // Assign partial products
    assign {a23b0,a22b0,a21b0,a20b0,a19b0,a18b0,a17b0,a16b0,a15b0,a14b0,a13b0,a12b0,a11b0,a10b0,a9b0,a8b0,a7b0,a6b0,a5b0,a4b0,a3b0,a2b0,a1b0,a0b0} = p0;
    assign {a23b1,a22b1,a21b1,a20b1,a19b1,a18b1,a17b1,a16b1,a15b1,a14b1,a13b1,a12b1,a11b1,a10b1,a9b1,a8b1,a7b1,a6b1,a5b1,a4b1,a3b1,a2b1,a1b1,a0b1} = p1;
    assign {a23b2,a22b2,a21b2,a20b2,a19b2,a18b2,a17b2,a16b2,a15b2,a14b2,a13b2,a12b2,a11b2,a10b2,a9b2,a8b2,a7b2,a6b2,a5b2,a4b2,a3b2,a2b2,a1b2,a0b2} = p2;
    assign {a23b3,a22b3,a21b3,a20b3,a19b3,a18b3,a17b3,a16b3,a15b3,a14b3,a13b3,a12b3,a11b3,a10b3,a9b3,a8b3,a7b3,a6b3,a5b3,a4b3,a3b3,a2b3,a1b3,a0b3} = p3;
    assign {a23b4,a22b4,a21b4,a20b4,a19b4,a18b4,a17b4,a16b4,a15b4,a14b4,a13b4,a12b4,a11b4,a10b4,a9b4,a8b4,a7b4,a6b4,a5b4,a4b4,a3b4,a2b4,a1b4,a0b4} = p4;
    assign {a23b5,a22b5,a21b5,a20b5,a19b5,a18b5,a17b5,a16b5,a15b5,a14b5,a13b5,a12b5,a11b5,a10b5,a9b5,a8b5,a7b5,a6b5,a5b5,a4b5,a3b5,a2b5,a1b5,a0b5} = p5;
    assign {a23b6,a22b6,a21b6,a20b6,a19b6,a18b6,a17b6,a16b6,a15b6,a14b6,a13b6,a12b6,a11b6,a10b6,a9b6,a8b6,a7b6,a6b6,a5b6,a4b6,a3b6,a2b6,a1b6,a0b6} = p6;
    assign {a23b7,a22b7,a21b7,a20b7,a19b7,a18b7,a17b7,a16b7,a15b7,a14b7,a13b7,a12b7,a11b7,a10b7,a9b7,a8b7,a7b7,a6b7,a5b7,a4b7,a3b7,a2b7,a1b7,a0b7} = p7;
    assign {a23b8,a22b8,a21b8,a20b8,a19b8,a18b8,a17b8,a16b8,a15b8,a14b8,a13b8,a12b8,a11b8,a10b8,a9b8,a8b8,a7b8,a6b8,a5b8,a4b8,a3b8,a2b8,a1b8,a0b8} = p8;
    assign {a23b9,a22b9,a21b9,a20b9,a19b9,a18b9,a17b9,a16b9,a15b9,a14b9,a13b9,a12b9,a11b9,a10b9,a9b9,a8b9,a7b9,a6b9,a5b9,a4b9,a3b9,a2b9,a1b9,a0b9} = p9;
    assign {a23b10,a22b10,a21b10,a20b10,a19b10,a18b10,a17b10,a16b10,a15b10,a14b10,a13b10,a12b10,a11b10,a10b10,a9b10,a8b10,a7b10,a6b10,a5b10,a4b10,a3b10,a2b10,a1b10,a0b10} = p10;
    assign {a23b11,a22b11,a21b11,a20b11,a19b11,a18b11,a17b11,a16b11,a15b11,a14b11,a13b11,a12b11,a11b11,a10b11,a9b11,a8b11,a7b11,a6b11,a5b11,a4b11,a3b11,a2b11,a1b11,a0b11} = p11;
    assign {a23b12,a22b12,a21b12,a20b12,a19b12,a18b12,a17b12,a16b12,a15b12,a14b12,a13b12,a12b12,a11b12,a10b12,a9b12,a8b12,a7b12,a6b12,a5b12,a4b12,a3b12,a2b12,a1b12,a0b12} = p12;
    assign {a23b13,a22b13,a21b13,a20b13,a19b13,a18b13,a17b13,a16b13,a15b13,a14b13,a13b13,a12b13,a11b13,a10b13,a9b13,a8b13,a7b13,a6b13,a5b13,a4b13,a3b13,a2b13,a1b13,a0b13} = p13;
    assign {a23b14,a22b14,a21b14,a20b14,a19b14,a18b14,a17b14,a16b14,a15b14,a14b14,a13b14,a12b14,a11b14,a10b14,a9b14,a8b14,a7b14,a6b14,a5b14,a4b14,a3b14,a2b14,a1b14,a0b14} = p14;
    assign {a23b15,a22b15,a21b15,a20b15,a19b15,a18b15,a17b15,a16b15,a15b15,a14b15,a13b15,a12b15,a11b15,a10b15,a9b15,a8b15,a7b15,a6b15,a5b15,a4b15,a3b15,a2b15,a1b15,a0b15} = p15;
    assign {a23b16,a22b16,a21b16,a20b16,a19b16,a18b16,a17b16,a16b16,a15b16,a14b16,a13b16,a12b16,a11b16,a10b16,a9b16,a8b16,a7b16,a6b16,a5b16,a4b16,a3b16,a2b16,a1b16,a0b16} = p16;
    assign {a23b17,a22b17,a21b17,a20b17,a19b17,a18b17,a17b17,a16b17,a15b17,a14b17,a13b17,a12b17,a11b17,a10b17,a9b17,a8b17,a7b17,a6b17,a5b17,a4b17,a3b17,a2b17,a1b17,a0b17} = p17;
    assign {a23b18,a22b18,a21b18,a20b18,a19b18,a18b18,a17b18,a16b18,a15b18,a14b18,a13b18,a12b18,a11b18,a10b18,a9b18,a8b18,a7b18,a6b18,a5b18,a4b18,a3b18,a2b18,a1b18,a0b18} = p18;
    assign {a23b19,a22b19,a21b19,a20b19,a19b19,a18b19,a17b19,a16b19,a15b19,a14b19,a13b19,a12b19,a11b19,a10b19,a9b19,a8b19,a7b19,a6b19,a5b19,a4b19,a3b19,a2b19,a1b19,a0b19} = p19;
    assign {a23b20,a22b20,a21b20,a20b20,a19b20,a18b20,a17b20,a16b20,a15b20,a14b20,a13b20,a12b20,a11b20,a10b20,a9b20,a8b20,a7b20,a6b20,a5b20,a4b20,a3b20,a2b20,a1b20,a0b20} = p20;
    assign {a23b21,a22b21,a21b21,a20b21,a19b21,a18b21,a17b21,a16b21,a15b21,a14b21,a13b21,a12b21,a11b21,a10b21,a9b21,a8b21,a7b21,a6b21,a5b21,a4b21,a3b21,a2b21,a1b21,a0b21} = p21;
    assign {a23b22,a22b22,a21b22,a20b22,a19b22,a18b22,a17b22,a16b22,a15b22,a14b22,a13b22,a12b22,a11b22,a10b22,a9b22,a8b22,a7b22,a6b22,a5b22,a4b22,a3b22,a2b22,a1b22,a0b22} = p22;
    assign {a23b23,a22b23,a21b23,a20b23,a19b23,a18b23,a17b23,a16b23,a15b23,a14b23,a13b23,a12b23,a11b23,a10b23,a9b23,a8b23,a7b23,a6b23,a5b23,a4b23,a3b23,a2b23,a1b23,a0b23} = p23;

    // ---- Dadda reduction tree (stages 1-8, unchanged from original) ----
    wire s20_1,c20_1,s21_2_1,c21_2_1,s22_3_1,c22_3_1,s23_4_1,c23_4_1,s24_5_1,c24_5_1,s25_5_1,c25_5_1;
    wire s21_1_1,c21_1_1,s22_1_1,c22_1_1,s22_2_1,c22_2_1,s23_1_1,c23_1_1,s23_2_1,c23_2_1,s23_3_1,c23_3_1;
    wire s24_1_1,c24_1_1,s24_2_1,c24_2_1,s24_3_1,c24_3_1,s24_4_1,c24_4_1,s25_1_1,c25_1_1,s25_2_1,c25_2_1,s25_3_1,c25_3_1;
    wire s25_4_1,c25_4_1,s26_1_1,c26_1_1,s26_2_1,c26_2_1,s26_3_1,c26_3_1,s26_4_1,c26_4_1;
    wire s27_1_1,c27_1_1,s27_2_1,c27_2_1,s27_3_1,c27_3_1,s28_1_1,c28_1_1,s28_2_1,c28_2_1,s29_1,c29_1;
    wire s14_2,c14_2,s15_1_2,c15_1_2,s15_2_2,c15_2_2,s16_1_2,c16_1_2,s16_2_2,c16_2_2,s16_3_2,c16_3_2;
    wire s17_1_2,c17_1_2,s17_2_2,c17_2_2,s17_3_2,c17_3_2,s17_4_2,c17_4_2;
    wire s18_1_2,c18_1_2,s18_2_2,c18_2_2,s18_3_2,c18_3_2,s18_4_2,c18_4_2,s18_5_2,c18_5_2;
    wire s19_1_2,c19_1_2,s19_2_2,c19_2_2,s19_3_2,c19_3_2,s19_4_2,c19_4_2,s19_5_2,c19_5_2,s19_6_2,c19_6_2;
    wire s20_1_2,c20_1_2,s20_2_2,c20_2_2,s20_3_2,c20_3_2;

    // stage-1
    HA ha1(a1b18,a0b19,s20_1,c20_1);
    FA fa1(a4b16,a3b17,a2b18,s21_1_1,c21_1_1);
    HA ha2(a1b19,a0b20,s21_2_1,c21_2_1);
    FA fa2(a7b14,a6b15,a5b16,s22_1_1,c22_1_1);
    FA fa3(a4b17,a3b18,a2b19,s22_2_1,c22_2_1);
    HA ha3(a1b20,a0b21,s22_3_1,c22_3_1);
    FA fa4(a10b12,a9b13,a8b14,s23_1_1,c23_1_1);
    FA fa5(a7b15,a6b16,a5b17,s23_2_1,c23_2_1);
    FA fa6(a4b18,a3b19,a2b20,s23_3_1,c23_3_1);
    HA ha4(a1b21,a0b22,s23_4_1,c23_4_1);
    FA fa7(a13b10,a12b11,a11b12,s24_1_1,c24_1_1);
    FA fa8(a10b13,a9b14,a8b15,s24_2_1,c24_2_1);
    FA fa9(a7b16,a6b17,a5b18,s24_3_1,c24_3_1);
    FA fa10(a4b19,a3b20,a2b21,s24_4_1,c24_4_1);
    HA ha5(a1b22,a0b23,s24_5_1,c24_5_1);
    FA fa11(a14b10,a13b11,a12b12,s25_1_1,c25_1_1);
    FA fa12(a11b13,a10b14,a9b15,s25_2_1,c25_2_1);
    FA fa13(a8b16,a7b17,a6b18,s25_3_1,c25_3_1);
    FA fa14(a5b19,a4b20,a3b21,s25_4_1,c25_4_1);
    HA ha6(a2b22,a1b23,s25_5_1,c25_5_1);
    FA fa15(a13b12,a12b13,a11b14,s26_1_1,c26_1_1);
    FA fa16(a10b15,a9b16,a8b17,s26_2_1,c26_2_1);
    FA fa17(a7b18,a6b19,a5b20,s26_3_1,c26_3_1);
    FA fa18(a4b21,a3b22,a2b23,s26_4_1,c26_4_1);
    FA fa19(a11b15,a10b16,a9b17,s27_1_1,c27_1_1);
    FA fa20(a8b18,a7b19,a6b20,s27_2_1,c27_2_1);
    FA fa21(a5b21,a4b22,a3b23,s27_3_1,c27_3_1);
    FA fa22(a9b18,a8b19,a7b20,s28_1_1,c28_1_1);
    FA fa23(a6b21,a5b22,a4b23,s28_2_1,c28_2_1);
    FA fa24(a7b21,a6b22,a5b23,s29_1,c29_1);

    // stage-2
    HA ha7(a1b12,a0b13,s14_2,c14_2);
    FA fa25(a4b10,a3b11,a2b12,s15_1_2,c15_1_2);
    HA ha8(a1b13,a0b14,s15_2_2,c15_2_2);
    FA fa26(a7b8,a6b9,a5b10,s16_1_2,c16_1_2);
    FA fa27(a4b11,a3b12,a2b13,s16_2_2,c16_2_2);
    HA ha9(a1b14,a0b15,s16_3_2,c16_3_2);
    FA fa28(a10b6,a9b7,a8b8,s17_1_2,c17_1_2);
    FA fa29(a7b9,a6b10,a5b11,s17_2_2,c17_2_2);
    FA fa30(a4b12,a3b13,a2b14,s17_3_2,c17_3_2);
    HA ha10(a1b15,a0b16,s17_4_2,c17_4_2);
    FA fa31(a13b4,a12b5,a11b6,s18_1_2,c18_1_2);
    FA fa32(a10b7,a9b8,a8b9,s18_2_2,c18_2_2);
    FA fa33(a7b10,a6b11,a5b12,s18_3_2,c18_3_2);
    FA fa34(a4b13,a3b14,a2b15,s18_4_2,c18_4_2);
    HA ha11(a1b16,a0b17,s18_5_2,c18_5_2);
    FA fa35(a16b2,a15b3,a14b4,s19_1_2,c19_1_2);
    FA fa36(a13b5,a12b6,a11b7,s19_2_2,c19_2_2);
    FA fa37(a10b8,a9b9,a8b10,s19_3_2,c19_3_2);
    FA fa38(a7b11,a6b12,a5b13,s19_4_2,c19_4_2);
    FA fa39(a4b14,a3b15,a2b16,s19_5_2,c19_5_2);
    HA ha12(a1b17,a0b18,s19_6_2,c19_6_2);

    wire s20_4_2,c20_4_2,s20_5_2,c20_5_2,s20_6_2,c20_6_2;
    wire s21_1_2,c21_1_2,s21_2_2,c21_2_2,s21_3_2,c21_3_2,s21_4_2,c21_4_2,s21_5_2,c21_5_2,s21_6_2,c21_6_2;
    wire s22_1_2,c22_1_2,s22_2_2,c22_2_2,s22_3_2,c22_3_2,s22_4_2,c22_4_2,s22_5_2,c22_5_2,s22_6_2,c22_6_2;

    FA fa40(a18b1,a17b2,a16b3,s20_1_2,c20_1_2);
    FA fa41(a15b4,a14b5,a13b6,s20_2_2,c20_2_2);
    FA fa42(a12b7,a11b8,a10b9,s20_3_2,c20_3_2);
    FA fa43(a9b10,a8b11,a7b12,s20_4_2,c20_4_2);
    FA fa44(a6b13,a5b14,a4b15,s20_5_2,c20_5_2);
    FA fa45(a3b16,a2b17,s20_1,s20_6_2,c20_6_2);
    FA fa46(a19b1,a18b2,a17b3,s21_1_2,c21_1_2);
    FA fa47(a16b4,a15b5,a14b6,s21_2_2,c21_2_2);
    FA fa48(a13b7,a12b8,a11b9,s21_3_2,c21_3_2);
    FA fa49(a10b10,a9b11,a8b12,s21_4_2,c21_4_2);
    FA fa50(a7b13,a6b14,a5b15,s21_5_2,c21_5_2);
    FA fa51(s21_1_1,s21_2_1,c20_1,s21_6_2,c21_6_2);
    FA fa52(a20b1,a19b2,a18b3,s22_1_2,c22_1_2);
    FA fa53(a17b4,a16b5,a15b6,s22_2_2,c22_2_2);
    FA fa54(a14b7,a13b8,a12b9,s22_3_2,c22_3_2);
    FA fa55(a11b10,a10b11,a9b12,s22_4_2,c22_4_2);
    FA fa56(a8b13,s22_1_1,s22_2_1,s22_5_2,c22_5_2);
    FA fa57(s22_3_1,c21_1_1,c21_2_1,s22_6_2,c22_6_2);

    wire s23_1_2,c23_1_2,s23_2_2,c23_2_2,s23_3_2,c23_3_2,s23_4_2,c23_4_2,s23_5_2,c23_5_2,s23_6_2,c23_6_2;
    wire s24_1_2,c24_1_2,s24_2_2,c24_2_2,s24_3_2,c24_3_2,s24_4_2,c24_4_2,s24_5_2,c24_5_2,s24_6_2,c24_6_2;
    wire s25_1_2,c25_1_2,s25_2_2,c25_2_2,s25_3_2,c25_3_2,s25_4_2,c25_4_2,s25_5_2,c25_5_2,s25_6_2,c25_6_2;

    FA fa58(a21b1,a20b2,a19b3,s23_1_2,c23_1_2);
    FA fa59(a18b4,a17b5,a16b6,s23_2_2,c23_2_2);
    FA fa60(a15b7,a14b8,a13b9,s23_3_2,c23_3_2);
    FA fa61(a12b10,a11b11,s23_1_1,s23_4_2,c23_4_2);
    FA fa62(s23_2_1,s23_3_1,s23_4_1,s23_5_2,c23_5_2);
    FA fa63(c22_1_1,c22_2_1,c22_3_1,s23_6_2,c23_6_2);
    FA fa64(a22b1,a21b2,a20b3,s24_1_2,c24_1_2);
    FA fa65(a19b4,a18b5,a17b6,s24_2_2,c24_2_2);
    FA fa66(a16b7,a15b8,a14b9,s24_3_2,c24_3_2);
    FA fa67(s24_1_1,s24_2_1,s24_3_1,s24_4_2,c24_4_2);
    FA fa68(s24_4_1,s24_5_1,c23_1_1,s24_5_2,c24_5_2);
    FA fa69(c23_2_1,c23_3_1,c23_4_1,s24_6_2,c24_6_2);
    FA fa70(a22b2,a21b3,a20b4,s25_1_2,c25_1_2);
    FA fa71(a19b5,a18b6,a17b7,s25_2_2,c25_2_2);
    FA fa72(a16b8,a15b9,s25_1_1,s25_3_2,c25_3_2);
    FA fa73(s25_2_1,s25_3_1,s25_4_1,s25_4_2,c25_4_2);
    FA fa74(s25_5_1,c24_1_1,c24_2_1,s25_5_2,c25_5_2);
    FA fa75(c24_3_1,c24_4_1,c24_5_1,s25_6_2,c25_6_2);

    wire s26_1_2,c26_1_2,s26_2_2,c26_2_2,s26_3_2,c26_3_2,s26_4_2,c26_4_2,s26_5_2,c26_5_2,s26_6_2,c26_6_2;
    wire s27_1_2,c27_1_2,s27_2_2,c27_2_2,s27_3_2,c27_3_2,s27_4_2,c27_4_2,s27_5_2,c27_5_2,s27_6_2,c27_6_2;
    wire s28_1_2,c28_1_2,s28_2_2,c28_2_2,s28_3_2,c28_3_2,s28_4_2,c28_4_2,s28_5_2,c28_5_2,s28_6_2,c28_6_2;

    FA fa76(a22b3,a21b4,a20b5,s26_1_2,c26_1_2);
    FA fa77(a19b6,a18b7,a17b8,s26_2_2,c26_2_2);
    FA fa78(a16b9,a15b10,a14b11,s26_3_2,c26_3_2);
    FA fa79(s26_1_1,s26_2_1,s26_3_1,s26_4_2,c26_4_2);
    FA fa80(s26_4_1,c25_1_1,c25_2_1,s26_5_2,c26_5_2);
    FA fa81(c25_3_1,c25_4_1,c25_5_1,s26_6_2,c26_6_2);
    FA fa82(a22b4,a21b5,a20b6,s27_1_2,c27_1_2);
    FA fa83(a19b7,a18b8,a17b9,s27_2_2,c27_2_2);
    FA fa84(a16b10,a15b11,a14b12,s27_3_2,c27_3_2);
    FA fa85(a13b13,a12b14,s27_1_1,s27_4_2,c27_4_2);
    FA fa86(s27_2_1,s27_3_1,c26_1_1,s27_5_2,c27_5_2);
    FA fa87(c26_2_1,c26_3_1,c26_4_1,s27_6_2,c27_6_2);
    FA fa88(a22b5,a21b6,a20b7,s28_1_2,c28_1_2);
    FA fa89(a19b8,a18b9,a17b10,s28_2_2,c28_2_2);
    FA fa90(a16b11,a15b12,a14b13,s28_3_2,c28_3_2);
    FA fa91(a13b14,a12b15,a11b16,s28_4_2,c28_4_2);
    FA fa92(a10b17,s28_1_1,s28_2_1,s28_5_2,c28_5_2);
    FA fa93(c27_1_1,c27_2_1,c27_3_1,s28_6_2,c28_6_2);

    wire s29_1_2,c29_1_2,s29_2_2,c29_2_2,s29_3_2,c29_3_2,s29_4_2,c29_4_2,s29_5_2,c29_5_2,s29_6_2,c29_6_2;
    wire s30_1_2,c30_1_2,s30_2_2,c30_2_2,s30_3_2,c30_3_2,s30_4_2,c30_4_2,s30_5_2,c30_5_2,s30_6_2,c30_6_2;
    wire s31_1_2,c31_1_2,s31_2_2,c31_2_2,s31_3_2,c31_3_2,s31_4_2,c31_4_2,s31_5_2,c31_5_2;
    wire s32_1_2,c32_1_2,s32_2_2,c32_2_2,s32_3_2,c32_3_2,s32_4_2,c32_4_2;

    FA fa94(a22b6,a21b7,a20b8,s29_1_2,c29_1_2);
    FA fa95(a19b9,a18b10,a17b11,s29_2_2,c29_2_2);
    FA fa96(a16b12,a15b13,a14b14,s29_3_2,c29_3_2);
    FA fa97(a13b15,a12b16,a11b17,s29_4_2,c29_4_2);
    FA fa98(a10b18,a9b19,a8b20,s29_5_2,c29_5_2);
    FA fa99(s29_1,c28_1_1,c28_2_1,s29_6_2,c29_6_2);
    FA fa100(a22b7,a21b8,a20b9,s30_1_2,c30_1_2);
    FA fa101(a19b10,a18b11,a17b12,s30_2_2,c30_2_2);
    FA fa102(a16b13,a15b14,a14b15,s30_3_2,c30_3_2);
    FA fa103(a13b16,a12b17,a11b18,s30_4_2,c30_4_2);
    FA fa104(a10b19,a9b20,a8b21,s30_5_2,c30_5_2);
    FA fa105(a7b22,a6b23,c29_1,s30_6_2,c30_6_2);
    FA fa106(a21b9,a20b10,a19b11,s31_1_2,c31_1_2);
    FA fa107(a18b12,a17b13,a16b14,s31_2_2,c31_2_2);
    FA fa108(a15b15,a14b16,a13b17,s31_3_2,c31_3_2);
    FA fa109(a12b18,a11b19,a10b20,s31_4_2,c31_4_2);
    FA fa110(a9b21,a8b22,a7b23,s31_5_2,c31_5_2);
    FA fa111(a19b12,a18b13,a17b14,s32_1_2,c32_1_2);
    FA fa112(a16b15,a15b16,a14b17,s32_2_2,c32_2_2);
    FA fa113(a13b18,a12b19,a11b20,s32_3_2,c32_3_2);
    FA fa114(a10b21,a9b22,a8b23,s32_4_2,c32_4_2);

    wire s33_1_2,c33_1_2,s33_2_2,c33_2_2,s33_3_2,c33_3_2;
    wire s34_1_2,c34_1_2,s34_2_2,c34_2_2,s35_2,c35_2;

    FA fa115(a17b15,a16b16,a15b17,s33_1_2,c33_1_2);
    FA fa116(a14b18,a13b19,a12b20,s33_2_2,c33_2_2);
    FA fa117(a11b21,a10b22,a9b23,s33_3_2,c33_3_2);
    FA fa118(a15b18,a14b19,a13b20,s34_1_2,c34_1_2);
    FA fa119(a12b21,a11b22,a10b23,s34_2_2,c34_2_2);
    FA fa120(a13b21,a12b22,a11b23,s35_2,c35_2);

    // stage-3
    wire s10_3,c10_3,s11_1_3,c11_1_3,s11_2_3,c11_2_3,s12_1_3,c12_1_3,s12_2_3,c12_2_3,s12_3_3,c12_3_3;
    wire s13_1_3,c13_1_3,s13_2_3,c13_2_3,s13_3_3,c13_3_3,s13_4_3,c13_4_3;
    wire s14_1_3,c14_1_3,s14_2_3,c14_2_3,s14_3_3,c14_3_3,s14_4_3,c14_4_3;
    wire s15_1_3,c15_1_3,s15_2_3,c15_2_3,s15_3_3,c15_3_3,s15_4_3,c15_4_3;
    wire s16_1_3,c16_1_3,s16_2_3,c16_2_3,s16_3_3,c16_3_3,s16_4_3,c16_4_3;

    HA ha13(a1b8,a0b9,s10_3,c10_3);
    FA fa121(a4b6,a3b7,a2b8,s11_1_3,c11_1_3);
    HA ha14(a1b9,a0b10,s11_2_3,c11_2_3);
    FA fa122(a7b4,a6b5,a5b6,s12_1_3,c12_1_3);
    FA fa123(a4b7,a3b8,a2b9,s12_2_3,c12_2_3);
    HA ha15(a1b10,a0b11,s12_3_3,c12_3_3);
    FA fa124(a10b2,a9b3,a8b4,s13_1_3,c13_1_3);
    FA fa125(a7b5,a6b6,a5b7,s13_2_3,c13_2_3);
    FA fa126(a4b8,a3b9,a2b10,s13_3_3,c13_3_3);
    HA ha16(a1b11,a0b12,s13_4_3,c13_4_3);
    FA fa127(a12b1,a11b2,a10b3,s14_1_3,c14_1_3);
    FA fa128(a9b4,a8b5,a7b6,s14_2_3,c14_2_3);
    FA fa129(a6b7,a5b8,a4b9,s14_3_3,c14_3_3);
    FA fa130(a3b10,a2b11,s14_2,s14_4_3,c14_4_3);
    FA fa131(a13b1,a12b2,a11b3,s15_1_3,c15_1_3);
    FA fa132(a10b4,a9b5,a8b6,s15_2_3,c15_2_3);
    FA fa133(a7b7,a6b8,a5b9,s15_3_3,c15_3_3);
    FA fa134(s15_1_2,s15_2_2,c14_2,s15_4_3,c15_4_3);
    FA fa135(a14b1,a13b2,a12b3,s16_1_3,c16_1_3);
    FA fa136(a11b4,a10b5,a9b6,s16_2_3,c16_2_3);
    FA fa137(a8b7,s16_1_2,s16_2_2,s16_3_3,c16_3_3);
    FA fa138(s16_3_2,c15_1_2,c15_2_2,s16_4_3,c16_4_3);

    wire s17_1_3,c17_1_3,s17_2_3,c17_2_3,s17_3_3,c17_3_3,s17_4_3,c17_4_3,s18_1_3,c18_1_3,s18_2_3,c18_2_3;
    wire s18_3_3,c18_3_3,s18_4_3,c18_4_3,s19_1_3,c19_1_3,s19_2_3,c19_2_3,s19_3_3,c19_3_3,s19_4_3,c19_4_3;
    wire s20_1_3,c20_1_3,s20_2_3,c20_2_3,s20_3_3,c20_3_3,s20_4_3,c20_4_3;
    wire s21_1_3,c21_1_3,s21_2_3,c21_2_3,s21_3_3,c21_3_3,s21_4_3,c21_4_3;
    wire s22_1_3,c22_1_3,s22_2_3,c22_2_3,s22_3_3,c22_3_3,s22_4_3,c22_4_3;

    FA fa139(a15b1,a14b2,a13b3,s17_1_3,c17_1_3);
    FA fa140(a12b4,a11b5,s17_1_2,s17_2_3,c17_2_3);
    FA fa141(s17_2_2,s17_3_2,s17_4_2,s17_3_3,c17_3_3);
    FA fa142(c16_1_2,c16_2_2,c16_3_2,s17_4_3,c17_4_3);
    FA fa143(a16b1,a15b2,a14b3,s18_1_3,c18_1_3);
    FA fa144(s18_1_2,s18_2_2,s18_3_2,s18_2_3,c18_2_3);
    FA fa145(s18_4_2,s18_5_2,c17_1_2,s18_3_3,c18_3_3);
    FA fa146(c17_2_2,c17_3_2,c17_4_2,s18_4_3,c18_4_3);
    FA fa147(a17b1,s19_1_2,s19_2_2,s19_1_3,c19_1_3);
    FA fa148(s19_3_2,s19_4_2,s19_5_2,s19_2_3,c19_2_3);
    FA fa149(s19_6_2,c18_1_2,c18_2_2,s19_3_3,c19_3_3);
    FA fa150(c18_3_2,c18_4_2,c18_5_2,s19_4_3,c19_4_3);
    FA fa151(s20_1_2,s20_2_2,s20_3_2,s20_1_3,c20_1_3);
    FA fa152(s20_4_2,s20_5_2,s20_6_2,s20_2_3,c20_2_3);
    FA fa153(c19_1_2,c19_2_2,c19_3_2,s20_3_3,c20_3_3);
    FA fa154(c19_4_2,c19_5_2,c19_6_2,s20_4_3,c20_4_3);
    FA fa155(s21_1_2,s21_2_2,s21_3_2,s21_1_3,c21_1_3);
    FA fa156(s21_4_2,s21_5_2,s21_6_2,s21_2_3,c21_2_3);
    FA fa157(c20_1_2,c20_2_2,c20_3_2,s21_3_3,c21_3_3);
    FA fa158(c20_4_2,c20_5_2,c20_6_2,s21_4_3,c21_4_3);
    FA fa159(s22_1_2,s22_2_2,s22_3_2,s22_1_3,c22_1_3);
    FA fa160(s22_4_2,s22_5_2,s22_6_2,s22_2_3,c22_2_3);
    FA fa161(c21_1_2,c21_2_2,c21_3_2,s22_3_3,c22_3_3);
    FA fa162(c21_4_2,c21_5_2,c21_6_2,s22_4_3,c22_4_3);

    wire s23_1_3,c23_1_3,s23_2_3,c23_2_3,s23_3_3,c23_3_3,s23_4_3,c23_4_3;
    wire s24_1_3,c24_1_3,s24_2_3,c24_2_3,s24_3_3,c24_3_3,s24_4_3,c24_4_3;
    wire s25_1_3,c25_1_3,s25_2_3,c25_2_3,s25_3_3,c25_3_3,s25_4_3,c25_4_3;
    wire s26_1_3,c26_1_3,s26_2_3,c26_2_3,s26_3_3,c26_3_3,s26_4_3,c26_4_3;
    wire s27_1_3,c27_1_3,s27_2_3,c27_2_3,s27_3_3,c27_3_3,s27_4_3,c27_4_3;
    wire s28_1_3,c28_1_3,s28_2_3,c28_2_3,s28_3_3,c28_3_3,s28_4_3,c28_4_3;
    wire s29_1_3,c29_1_3,s29_2_3,c29_2_3,s29_3_3,c29_3_3,s29_4_3,c29_4_3;

    FA fa163(s23_1_2,s23_2_2,s23_3_2,s23_1_3,c23_1_3);
    FA fa164(s23_4_2,s23_5_2,s23_6_2,s23_2_3,c23_2_3);
    FA fa165(c22_1_2,c22_2_2,c22_3_2,s23_3_3,c23_3_3);
    FA fa166(c22_4_2,c22_5_2,c22_6_2,s23_4_3,c23_4_3);
    FA fa167(s24_1_2,s24_2_2,s24_3_2,s24_1_3,c24_1_3);
    FA fa168(s24_4_2,s24_5_2,s24_6_2,s24_2_3,c24_2_3);
    FA fa169(c23_1_2,c23_2_2,c23_3_2,s24_3_3,c24_3_3);
    FA fa170(c23_4_2,c23_5_2,c23_6_2,s24_4_3,c24_4_3);
    FA fa171(s25_1_2,s25_2_2,s25_3_2,s25_1_3,c25_1_3);
    FA fa172(s25_4_2,s25_5_2,s25_6_2,s25_2_3,c25_2_3);
    FA fa173(c24_1_2,c24_2_2,c24_3_2,s25_3_3,c25_3_3);
    FA fa174(c24_4_2,c24_5_2,c24_6_2,s25_4_3,c25_4_3);
    FA fa175(s26_1_2,s26_2_2,s26_3_2,s26_1_3,c26_1_3);
    FA fa176(s26_4_2,s26_5_2,s26_6_2,s26_2_3,c26_2_3);
    FA fa177(c25_1_2,c25_2_2,c25_3_2,s26_3_3,c26_3_3);
    FA fa178(c25_4_2,c25_5_2,c25_6_2,s26_4_3,c26_4_3);
    FA fa179(s27_1_2,s27_2_2,s27_3_2,s27_1_3,c27_1_3);
    FA fa180(s27_4_2,s27_5_2,s27_6_2,s27_2_3,c27_2_3);
    FA fa181(c26_1_2,c26_2_2,c26_3_2,s27_3_3,c27_3_3);
    FA fa182(c26_4_2,c26_5_2,c26_6_2,s27_4_3,c27_4_3);
    FA fa183(s28_1_2,s28_2_2,s28_3_2,s28_1_3,c28_1_3);
    FA fa184(s28_4_2,s28_5_2,s28_6_2,s28_2_3,c28_2_3);
    FA fa185(c27_1_2,c27_2_2,c27_3_2,s28_3_3,c28_3_3);
    FA fa186(c27_4_2,c27_5_2,c27_6_2,s28_4_3,c28_4_3);
    FA fa187(s29_1_2,s29_2_2,s29_3_2,s29_1_3,c29_1_3);
    FA fa188(s29_4_2,s29_5_2,s29_6_2,s29_2_3,c29_2_3);
    FA fa189(c28_1_2,c28_2_2,c28_3_2,s29_3_3,c29_3_3);
    FA fa190(c28_4_2,c28_5_2,c28_6_2,s29_4_3,c29_4_3);

    wire s30_1_3,c30_1_3,s30_2_3,c30_2_3,s30_3_3,c30_3_3,s30_4_3,c30_4_3;
    wire s31_1_3,c31_1_3,s31_2_3,c31_2_3,s31_3_3,c31_3_3,s31_4_3,c31_4_3;
    wire s32_1_3,c32_1_3,s32_2_3,c32_2_3,s32_3_3,c32_3_3,s32_4_3,c32_4_3;
    wire s33_1_3,c33_1_3,s33_2_3,c33_2_3,s33_3_3,c33_3_3,s33_4_3,c33_4_3;
    wire s34_1_3,c34_1_3,s34_2_3,c34_2_3,s34_3_3,c34_3_3,s34_4_3,c34_4_3;

    FA fa191(s30_1_2,s30_2_2,s30_3_2,s30_1_3,c30_1_3);
    FA fa192(s30_4_2,s30_5_2,s30_6_2,s30_2_3,c30_2_3);
    FA fa193(c29_1_2,c29_2_2,c29_3_2,s30_3_3,c30_3_3);
    FA fa194(c29_4_2,c29_5_2,c29_6_2,s30_4_3,c30_4_3);
    FA fa195(a22b8,s31_1_2,s31_2_2,s31_1_3,c31_1_3);
    FA fa196(s31_3_2,s31_4_2,s31_5_2,s31_2_3,c31_2_3);
    FA fa197(c30_1_2,c30_2_2,c30_3_2,s31_3_3,c31_3_3);
    FA fa198(c30_4_2,c30_5_2,c30_6_2,s31_4_3,c31_4_3);
    FA fa199(a22b9,a21b10,a20b11,s32_1_3,c32_1_3);
    FA fa200(s32_1_2,s32_2_2,s32_3_2,s32_2_3,c32_2_3);
    FA fa201(s32_4_2,c31_1_2,c31_2_2,s32_3_3,c32_3_3);
    FA fa202(c31_3_2,c31_4_2,c31_5_2,s32_4_3,c32_4_3);
    FA fa203(a22b10,a21b11,a20b12,s33_1_3,c33_1_3);
    FA fa204(a19b13,a18b14,s33_1_2,s33_2_3,c33_2_3);
    FA fa205(s33_2_2,s33_3_2,c32_1_2,s33_3_3,c33_3_3);
    FA fa206(c32_2_2,c32_3_2,c32_4_2,s33_4_3,c33_4_3);
    FA fa207(a22b11,a21b12,a20b13,s34_1_3,c34_1_3);
    FA fa208(a19b14,a18b15,a17b16,s34_2_3,c34_2_3);
    FA fa209(a16b17,s34_1_2,s34_2_2,s34_3_3,c34_3_3);
    FA fa210(c33_1_2,c33_2_2,c33_3_2,s34_4_3,c34_4_3);

    wire s35_1_3,c35_1_3,s35_2_3,c35_2_3,s35_3_3,c35_3_3,s35_4_3,c35_4_3;
    wire s36_1_3,c36_1_3,s36_2_3,c36_2_3,s36_3_3,c36_3_3,s36_4_3,c36_4_3;
    wire s37_1_3,c37_1_3,s37_2_3,c37_2_3,s37_3_3,c37_3_3;
    wire s38_1_3,c38_1_3,s38_2_3,c38_2_3;
    wire s39_3,c39_3;

    FA fa211(a22b12,a21b13,a20b14,s35_1_3,c35_1_3);
    FA fa212(a19b15,a18b16,a17b17,s35_2_3,c35_2_3);
    FA fa213(a16b18,a15b19,a14b20,s35_3_3,c35_3_3);
    FA fa214(s35_2,c34_1_2,c34_2_2,s35_4_3,c35_4_3);
    FA fa215(a22b13,a21b14,a20b15,s36_1_3,c36_1_3);
    FA fa216(a19b16,a18b17,a17b18,s36_2_3,c36_2_3);
    FA fa217(a16b19,a15b20,a14b21,s36_3_3,c36_3_3);
    FA fa218(a13b22,a12b23,c35_2,s36_4_3,c36_4_3);
    FA fa219(a21b15,a20b16,a19b17,s37_1_3,c37_1_3);
    FA fa220(a18b18,a17b19,a16b20,s37_2_3,c37_2_3);
    FA fa221(a15b21,a14b22,a13b23,s37_3_3,c37_3_3);
    FA fa222(a19b18,a18b19,a17b20,s38_1_3,c38_1_3);
    FA fa223(a16b21,a15b22,a14b23,s38_2_3,c38_2_3);
    FA fa224(a17b21,a16b22,a15b23,s39_3,c39_3);

    // stage-4
    wire s7_4,c7_4,s8_1_4,c8_1_4,s8_2_4,c8_2_4,s9_1_4,c9_1_4;
    wire s9_2_4,c9_2_4,s9_3_4,c9_3_4;
    wire s10_1_4,c10_1_4,s10_2_4,c10_2_4,s10_3_4,c10_3_4;
    wire s11_1_4,c11_1_4,s11_2_4,c11_2_4,s11_3_4,c11_3_4;
    wire s12_1_4,c12_1_4,s12_2_4,c12_2_4,s12_3_4,c12_3_4;
    wire s13_1_4,c13_1_4,s13_2_4,c13_2_4,s13_3_4,c13_3_4;

    HA ha17(a1b5,a0b6,s7_4,c7_4);
    FA fa225(a4b3,a3b4,a2b5,s8_1_4,c8_1_4);
    HA ha18(a1b6,a0b7,s8_2_4,c8_2_4);
    FA fa226(a7b1,a6b2,a5b3,s9_1_4,c9_1_4);
    FA fa227(a4b4,a3b5,a2b6,s9_2_4,c9_2_4);
    HA ha19(a1b7,a0b8,s9_3_4,c9_3_4);
    FA fa228(a9b0,a8b1,a7b2,s10_1_4,c10_1_4);
    FA fa229(a6b3,a5b4,a4b5,s10_2_4,c10_2_4);
    FA fa230(a3b6,a2b7,s10_3,s10_3_4,c10_3_4);
    FA fa231(a10b0,a9b1,a8b2,s11_1_4,c11_1_4);
    FA fa232(a7b3,a6b4,a5b5,s11_2_4,c11_2_4);
    FA fa233(s11_1_3,s11_2_3,c10_3,s11_3_4,c11_3_4);
    FA fa234(a11b0,a10b1,a9b2,s12_1_4,c12_1_4);
    FA fa235(a8b3,s12_1_3,s12_2_3,s12_2_4,c12_2_4);
    FA fa236(s12_3_3,c11_1_3,c11_2_3,s12_3_4,c12_3_4);
    FA fa237(a12b0,a11b1,s13_1_3,s13_1_4,c13_1_4);
    FA fa238(s13_2_3,s13_3_3,s13_4_3,s13_2_4,c13_2_4);
    FA fa239(c12_1_3,c12_2_3,c12_3_3,s13_3_4,c13_3_4);

    wire s14_1_4,c14_1_4,s14_2_4,c14_2_4,s14_3_4,c14_3_4;
    wire s15_1_4,c15_1_4,s15_2_4,c15_2_4,s15_3_4,c15_3_4;
    wire s16_1_4,c16_1_4,s16_2_4,c16_2_4,s16_3_4,c16_3_4;
    wire s17_1_4,c17_1_4,s17_2_4,c17_2_4,s17_3_4,c17_3_4;
    wire s18_1_4,c18_1_4,s18_2_4,c18_2_4,s18_3_4,c18_3_4;

    FA fa240(a13b0,s14_1_3,s14_2_3,s14_1_4,c14_1_4);
    FA fa241(s14_3_3,s14_4_3,c13_1_3,s14_2_4,c14_2_4);
    FA fa242(c13_2_3,c13_3_3,c13_4_3,s14_3_4,c14_3_4);
    FA fa243(a14b0,s15_1_3,s15_2_3,s15_1_4,c15_1_4);
    FA fa244(s15_3_3,s15_4_3,c14_1_3,s15_2_4,c15_2_4);
    FA fa245(c14_2_3,c14_3_3,c14_4_3,s15_3_4,c15_3_4);
    FA fa246(a15b0,s16_1_3,s16_2_3,s16_1_4,c16_1_4);
    FA fa247(s16_3_3,s16_4_3,c15_1_3,s16_2_4,c16_2_4);
    FA fa248(c15_2_3,c15_3_3,c15_4_3,s16_3_4,c16_3_4);
    FA fa249(a16b0,s17_1_3,s17_2_3,s17_1_4,c17_1_4);
    FA fa250(s17_3_3,s17_4_3,c16_1_3,s17_2_4,c17_2_4);
    FA fa251(c16_2_3,c16_3_3,c16_4_3,s17_3_4,c17_3_4);
    FA fa252(a17b0,s18_1_3,s18_2_3,s18_1_4,c18_1_4);
    FA fa253(s18_3_3,s18_4_3,c17_1_3,s18_2_4,c18_2_4);
    FA fa254(c17_2_3,c17_3_3,c17_4_3,s18_3_4,c18_3_4);

    wire s19_1_4,c19_1_4,s19_2_4,c19_2_4,s19_3_4,c19_3_4;
    wire s20_1_4,c20_1_4,s20_2_4,c20_2_4,s20_3_4,c20_3_4;
    wire s21_1_4,c21_1_4,s21_2_4,c21_2_4,s21_3_4,c21_3_4;
    wire s22_1_4,c22_1_4,s22_2_4,c22_2_4,s22_3_4,c22_3_4;
    wire s23_1_4,c23_1_4,s23_2_4,c23_2_4,s23_3_4,c23_3_4;

    FA fa255(a18b0,s19_1_3,s19_2_3,s19_1_4,c19_1_4);
    FA fa256(s19_3_3,s19_4_3,c18_1_3,s19_2_4,c19_2_4);
    FA fa257(c18_2_3,c18_3_3,c18_4_3,s19_3_4,c19_3_4);
    FA fa258(a19b0,s20_1_3,s20_2_3,s20_1_4,c20_1_4);
    FA fa259(s20_3_3,s20_4_3,c19_1_3,s20_2_4,c20_2_4);
    FA fa260(c19_2_3,c19_3_3,c19_4_3,s20_3_4,c20_3_4);
    FA fa261(a20b0,s21_1_3,s21_2_3,s21_1_4,c21_1_4);
    FA fa262(s21_3_3,s21_4_3,c20_1_3,s21_2_4,c21_2_4);
    FA fa263(c20_2_3,c20_3_3,c20_4_3,s21_3_4,c21_3_4);
    FA fa264(a21b0,s22_1_3,s22_2_3,s22_1_4,c22_1_4);
    FA fa265(s22_3_3,s22_4_3,c21_1_3,s22_2_4,c22_2_4);
    FA fa266(c21_2_3,c21_3_3,c21_4_3,s22_3_4,c22_3_4);
    FA fa267(a22b0,s23_1_3,s23_2_3,s23_1_4,c23_1_4);
    FA fa268(s23_3_3,s23_4_3,c22_1_3,s23_2_4,c23_2_4);
    FA fa269(c22_2_3,c22_3_3,c22_4_3,s23_3_4,c23_3_4);

    wire s24_1_4,c24_1_4,s24_2_4,c24_2_4,s24_3_4,c24_3_4;
    wire s25_1_4,c25_1_4,s25_2_4,c25_2_4,s25_3_4,c25_3_4;
    wire s26_1_4,c26_1_4,s26_2_4,c26_2_4,s26_3_4,c26_3_4;
    wire s27_1_4,c27_1_4,s27_2_4,c27_2_4,s27_3_4,c27_3_4;
    wire s28_1_4,c28_1_4,s28_2_4,c28_2_4,s28_3_4,c28_3_4;

    FA fa270(a23b0,s24_1_3,s24_2_3,s24_1_4,c24_1_4);
    FA fa271(s24_3_3,s24_4_3,c23_1_3,s24_2_4,c24_2_4);
    FA fa272(c23_2_3,c23_3_3,c23_4_3,s24_3_4,c24_3_4);
    FA fa273(a23b1,s25_1_3,s25_2_3,s25_1_4,c25_1_4);
    FA fa274(s25_3_3,s25_4_3,c24_1_3,s25_2_4,c25_2_4);
    FA fa275(c24_2_3,c24_3_3,c24_4_3,s25_3_4,c25_3_4);
    FA fa276(a23b2,s26_1_3,s26_2_3,s26_1_4,c26_1_4);
    FA fa277(s26_3_3,s26_4_3,c25_1_3,s26_2_4,c26_2_4);
    FA fa278(c25_2_3,c25_3_3,c25_4_3,s26_3_4,c26_3_4);
    FA fa279(a23b3,s27_1_3,s27_2_3,s27_1_4,c27_1_4);
    FA fa280(s27_3_3,s27_4_3,c26_1_3,s27_2_4,c27_2_4);
    FA fa281(c26_2_3,c26_3_3,c26_4_3,s27_3_4,c27_3_4);
    FA fa282(a23b4,s28_1_3,s28_2_3,s28_1_4,c28_1_4);
    FA fa283(s28_3_3,s28_4_3,c27_1_3,s28_2_4,c28_2_4);
    FA fa284(c27_2_3,c27_3_3,c27_4_3,s28_3_4,c28_3_4);

    wire s29_1_4,c29_1_4,s29_2_4,c29_2_4,s29_3_4,c29_3_4;
    wire s30_1_4,c30_1_4,s30_2_4,c30_2_4,s30_3_4,c30_3_4;
    wire s31_1_4,c31_1_4,s31_2_4,c31_2_4,s31_3_4,c31_3_4;
    wire s32_1_4,c32_1_4,s32_2_4,c32_2_4,s32_3_4,c32_3_4;
    wire s33_1_4,c33_1_4,s33_2_4,c33_2_4,s33_3_4,c33_3_4;

    FA fa285(a23b5,s29_1_3,s29_2_3,s29_1_4,c29_1_4);
    FA fa286(s29_3_3,s29_4_3,c28_1_3,s29_2_4,c29_2_4);
    FA fa287(c28_2_3,c28_3_3,c28_4_3,s29_3_4,c29_3_4);
    FA fa288(a23b6,s30_1_3,s30_2_3,s30_1_4,c30_1_4);
    FA fa289(s30_3_3,s30_4_3,c29_1_3,s30_2_4,c30_2_4);
    FA fa290(c29_2_3,c29_3_3,c29_4_3,s30_3_4,c30_3_4);
    FA fa291(a23b7,s31_1_3,s31_2_3,s31_1_4,c31_1_4);
    FA fa292(s31_3_3,s31_4_3,c30_1_3,s31_2_4,c31_2_4);
    FA fa293(c30_2_3,c30_3_3,c30_4_3,s31_3_4,c31_3_4);
    FA fa294(a23b8,s32_1_3,s32_2_3,s32_1_4,c32_1_4);
    FA fa295(s32_3_3,s32_4_3,c31_1_3,s32_2_4,c32_2_4);
    FA fa296(c31_2_3,c31_3_3,c31_4_3,s32_3_4,c32_3_4);
    FA fa297(a23b9,s33_1_3,s33_2_3,s33_1_4,c33_1_4);
    FA fa298(s33_3_3,s33_4_3,c32_1_3,s33_2_4,c33_2_4);
    FA fa299(c32_2_3,c32_3_3,c32_4_3,s33_3_4,c33_3_4);

    wire s34_1_4,c34_1_4,s34_2_4,c34_2_4,s34_3_4,c34_3_4;
    wire s35_1_4,c35_1_4,s35_2_4,c35_2_4,s35_3_4,c35_3_4;
    wire s36_1_4,c36_1_4,s36_2_4,c36_2_4,s36_3_4,c36_3_4;
    wire s37_1_4,c37_1_4,s37_2_4,c37_2_4,s37_3_4,c37_3_4;
    wire s38_1_4,c38_1_4,s38_2_4,c38_2_4,s38_3_4,c38_3_4;
    wire s39_1_4,c39_1_4,s39_2_4,c39_2_4,s39_3_4,c39_3_4;

    FA fa300(a23b10,s34_1_3,s34_2_3,s34_1_4,c34_1_4);
    FA fa301(s34_3_3,s34_4_3,c33_1_3,s34_2_4,c34_2_4);
    FA fa302(c33_2_3,c33_3_3,c33_4_3,s34_3_4,c34_3_4);
    FA fa303(a23b11,s35_1_3,s35_2_3,s35_1_4,c35_1_4);
    FA fa304(s35_3_3,s35_4_3,c34_1_3,s35_2_4,c35_2_4);
    FA fa305(c34_2_3,c34_3_3,c34_4_3,s35_3_4,c35_3_4);
    FA fa306(a23b12,s36_1_3,s36_2_3,s36_1_4,c36_1_4);
    FA fa307(s36_3_3,s36_4_3,c35_1_3,s36_2_4,c36_2_4);
    FA fa308(c35_2_3,c35_3_3,c35_4_3,s36_3_4,c36_3_4);
    FA fa309(a23b13,a22b14,s37_1_3,s37_1_4,c37_1_4);
    FA fa310(s37_2_3,s37_3_3,c36_1_3,s37_2_4,c37_2_4);
    FA fa311(c36_2_3,c36_3_3,c36_4_3,s37_3_4,c37_3_4);
    FA fa312(a23b14,a22b15,a21b16,s38_1_4,c38_1_4);
    FA fa313(a20b17,s38_1_3,s38_2_3,s38_2_4,c38_2_4);
    FA fa314(c37_1_3,c37_2_3,c37_3_3,s38_3_4,c38_3_4);
    FA fa315(a23b15,a22b16,a21b17,s39_1_4,c39_1_4);
    FA fa316(a20b18,a19b19,a18b20,s39_2_4,c39_2_4);
    FA fa317(s39_3,c38_1_3,c38_2_3,s39_3_4,c39_3_4);

    wire s40_1_4,c40_1_4,s40_2_4,c40_2_4,s40_3_4,c40_3_4;
    wire s41_1_4,c41_1_4,s41_2_4,c41_2_4;
    wire s42_4,c42_4;

    FA fa318(a23b16,a22b17,a21b18,s40_1_4,c40_1_4);
    FA fa319(a20b19,a19b20,a18b21,s40_2_4,c40_2_4);
    FA fa320(a17b22,a16b23,c39_3,s40_3_4,c40_3_4);
    FA fa321(a22b18,a21b19,a20b20,s41_1_4,c41_1_4);
    FA fa322(a19b21,a18b22,a17b23,s41_2_4,c41_2_4);
    FA fa323(a20b21,a19b22,a18b23,s42_4,c42_4);

    // stage-5
    wire s5_5,c5_5,s6_1_5,c6_1_5,s6_2_5,c6_2_5;
    wire s7_1_5,c7_1_5,s7_2_5,c7_2_5,s8_1_5,c8_1_5,s8_2_5,c8_2_5;
    wire s9_1_5,c9_1_5,s9_2_5,c9_2_5;

    HA ha20(a1b3,a0b4,s5_5,c5_5);
    FA fa324(a4b1,a3b2,a2b3,s6_1_5,c6_1_5);
    HA ha21(a1b4,a0b5,s6_2_5,c6_2_5);
    FA fa325(a6b0,a5b1,a4b2,s7_1_5,c7_1_5);
    FA fa326(a3b3,a2b4,s7_4,s7_2_5,c7_2_5);
    FA fa327(a7b0,a6b1,a5b2,s8_1_5,c8_1_5);
    FA fa328(s8_1_4,s8_2_4,c7_4,s8_2_5,c8_2_5);
    FA fa329(a8b0,s9_1_4,s9_2_4,s9_1_5,c9_1_5);
    FA fa330(s9_3_4,c8_1_4,c8_2_4,s9_2_5,c9_2_5);

    wire s10_1_5,c10_1_5,s10_2_5,c10_2_5;
    wire s11_1_5,c11_1_5,s11_2_5,c11_2_5;
    wire s12_1_5,c12_1_5,s12_2_5,c12_2_5;
    wire s13_1_5,c13_1_5,s13_2_5,c13_2_5;
    wire s14_1_5,c14_1_5,s14_2_5,c14_2_5;
    wire s15_1_5,c15_1_5,s15_2_5,c15_2_5;
    wire s16_1_5,c16_1_5,s16_2_5,c16_2_5;

    FA fa331(s10_1_4,s10_2_4,s10_3_4,s10_1_5,c10_1_5);
    FA fa332(c9_1_4,c9_2_4,c9_3_4,s10_2_5,c10_2_5);
    FA fa333(s11_1_4,s11_2_4,s11_3_4,s11_1_5,c11_1_5);
    FA fa334(c10_1_4,c10_2_4,c10_3_4,s11_2_5,c11_2_5);
    FA fa335(s12_1_4,s12_2_4,s12_3_4,s12_1_5,c12_1_5);
    FA fa336(c11_1_4,c11_2_4,c11_3_4,s12_2_5,c12_2_5);
    FA fa337(s13_1_4,s13_2_4,s13_3_4,s13_1_5,c13_1_5);
    FA fa338(c12_1_4,c12_2_4,c12_3_4,s13_2_5,c13_2_5);
    FA fa339(s14_1_4,s14_2_4,s14_3_4,s14_1_5,c14_1_5);
    FA fa340(c13_1_4,c13_2_4,c13_3_4,s14_2_5,c14_2_5);
    FA fa341(s15_1_4,s15_2_4,s15_3_4,s15_1_5,c15_1_5);
    FA fa342(c14_1_4,c14_2_4,c14_3_4,s15_2_5,c15_2_5);
    FA fa343(s16_1_4,s16_2_4,s16_3_4,s16_1_5,c16_1_5);
    FA fa344(c15_1_4,c15_2_4,c15_3_4,s16_2_5,c16_2_5);

    wire s17_1_5,c17_1_5,s17_2_5,c17_2_5;
    wire s18_1_5,c18_1_5,s18_2_5,c18_2_5;
    wire s19_1_5,c19_1_5,s19_2_5,c19_2_5;
    wire s20_1_5,c20_1_5,s20_2_5,c20_2_5;
    wire s21_1_5,c21_1_5,s21_2_5,c21_2_5;
    wire s22_1_5,c22_1_5,s22_2_5,c22_2_5;
    wire s23_1_5,c23_1_5,s23_2_5,c23_2_5;

    FA fa345(s17_1_4,s17_2_4,s17_3_4,s17_1_5,c17_1_5);
    FA fa346(c16_1_4,c16_2_4,c16_3_4,s17_2_5,c17_2_5);
    FA fa347(s18_1_4,s18_2_4,s18_3_4,s18_1_5,c18_1_5);
    FA fa348(c17_1_4,c17_2_4,c17_3_4,s18_2_5,c18_2_5);
    FA fa349(s19_1_4,s19_2_4,s19_3_4,s19_1_5,c19_1_5);
    FA fa350(c18_1_4,c18_2_4,c18_3_4,s19_2_5,c19_2_5);
    FA fa351(s20_1_4,s20_2_4,s20_3_4,s20_1_5,c20_1_5);
    FA fa352(c19_1_4,c19_2_4,c19_3_4,s20_2_5,c20_2_5);
    FA fa353(s21_1_4,s21_2_4,s21_3_4,s21_1_5,c21_1_5);
    FA fa354(c20_1_4,c20_2_4,c20_3_4,s21_2_5,c21_2_5);
    FA fa355(s22_1_4,s22_2_4,s22_3_4,s22_1_5,c22_1_5);
    FA fa356(c21_1_4,c21_2_4,c21_3_4,s22_2_5,c22_2_5);
    FA fa357(s23_1_4,s23_2_4,s23_3_4,s23_1_5,c23_1_5);
    FA fa358(c22_1_4,c22_2_4,c22_3_4,s23_2_5,c23_2_5);

    wire s24_1_5,c24_1_5,s24_2_5,c24_2_5;
    wire s25_1_5,c25_1_5,s25_2_5,c25_2_5;
    wire s26_1_5,c26_1_5,s26_2_5,c26_2_5;
    wire s27_1_5,c27_1_5,s27_2_5,c27_2_5;
    wire s28_1_5,c28_1_5,s28_2_5,c28_2_5;
    wire s29_1_5,c29_1_5,s29_2_5,c29_2_5;
    wire s30_1_5,c30_1_5,s30_2_5,c30_2_5;

    FA fa359(s24_1_4,s24_2_4,s24_3_4,s24_1_5,c24_1_5);
    FA fa360(c23_1_4,c23_2_4,c23_3_4,s24_2_5,c24_2_5);
    FA fa361(s25_1_4,s25_2_4,s25_3_4,s25_1_5,c25_1_5);
    FA fa362(c24_1_4,c24_2_4,c24_3_4,s25_2_5,c25_2_5);
    FA fa363(s26_1_4,s26_2_4,s26_3_4,s26_1_5,c26_1_5);
    FA fa364(c25_1_4,c25_2_4,c25_3_4,s26_2_5,c26_2_5);
    FA fa365(s27_1_4,s27_2_4,s27_3_4,s27_1_5,c27_1_5);
    FA fa366(c26_1_4,c26_2_4,c26_3_4,s27_2_5,c27_2_5);
    FA fa367(s28_1_4,s28_2_4,s28_3_4,s28_1_5,c28_1_5);
    FA fa368(c27_1_4,c27_2_4,c27_3_4,s28_2_5,c28_2_5);
    FA fa369(s29_1_4,s29_2_4,s29_3_4,s29_1_5,c29_1_5);
    FA fa370(c28_1_4,c28_2_4,c28_3_4,s29_2_5,c29_2_5);
    FA fa371(s30_1_4,s30_2_4,s30_3_4,s30_1_5,c30_1_5);
    FA fa372(c29_1_4,c29_2_4,c29_3_4,s30_2_5,c30_2_5);

    wire s31_1_5,c31_1_5,s31_2_5,c31_2_5;
    wire s32_1_5,c32_1_5,s32_2_5,c32_2_5;
    wire s33_1_5,c33_1_5,s33_2_5,c33_2_5;
    wire s34_1_5,c34_1_5,s34_2_5,c34_2_5;
    wire s35_1_5,c35_1_5,s35_2_5,c35_2_5;
    wire s36_1_5,c36_1_5,s36_2_5,c36_2_5;
    wire s37_1_5,c37_1_5,s37_2_5,c37_2_5;

    FA fa373(s31_1_4,s31_2_4,s31_3_4,s31_1_5,c31_1_5);
    FA fa374(c30_1_4,c30_2_4,c30_3_4,s31_2_5,c31_2_5);
    FA fa375(s32_1_4,s32_2_4,s32_3_4,s32_1_5,c32_1_5);
    FA fa376(c31_1_4,c31_2_4,c31_3_4,s32_2_5,c32_2_5);
    FA fa377(s33_1_4,s33_2_4,s33_3_4,s33_1_5,c33_1_5);
    FA fa378(c32_1_4,c32_2_4,c32_3_4,s33_2_5,c33_2_5);
    FA fa379(s34_1_4,s34_2_4,s34_3_4,s34_1_5,c34_1_5);
    FA fa380(c33_1_4,c33_2_4,c33_3_4,s34_2_5,c34_2_5);
    FA fa381(s35_1_4,s35_2_4,s35_3_4,s35_1_5,c35_1_5);
    FA fa382(c34_1_4,c34_2_4,c34_3_4,s35_2_5,c35_2_5);
    FA fa383(s36_1_4,s36_2_4,s36_3_4,s36_1_5,c36_1_5);
    FA fa384(c35_1_4,c35_2_4,c35_3_4,s36_2_5,c36_2_5);
    FA fa385(s37_1_4,s37_2_4,s37_3_4,s37_1_5,c37_1_5);
    FA fa386(c36_1_4,c36_2_4,c36_3_4,s37_2_5,c37_2_5);

    wire s38_1_5,c38_1_5,s38_2_5,c38_2_5;
    wire s39_1_5,c39_1_5,s39_2_5,c39_2_5;
    wire s40_1_5,c40_1_5,s40_2_5,c40_2_5;
    wire s41_1_5,c41_1_5,s41_2_5,c41_2_5;
    wire s42_1_5,c42_1_5,s42_2_5,c42_2_5;
    wire s43_1_5,c43_1_5,s43_2_5,c43_2_5;
    wire s44_5,c44_5;

    FA fa387(s38_1_4,s38_2_4,s38_3_4,s38_1_5,c38_1_5);
    FA fa388(c37_1_4,c37_2_4,c37_3_4,s38_2_5,c38_2_5);
    FA fa389(s39_1_4,s39_2_4,s39_3_4,s39_1_5,c39_1_5);
    FA fa390(c38_1_4,c38_2_4,c38_3_4,s39_2_5,c39_2_5);
    FA fa391(s40_1_4,s40_2_4,s40_3_4,s40_1_5,c40_1_5);
    FA fa392(c39_1_4,c39_2_4,c39_3_4,s40_2_5,c40_2_5);
    FA fa393(a23b17,s41_1_4,s41_2_4,s41_1_5,c41_1_5);
    FA fa394(c40_1_4,c40_2_4,c40_3_4,s41_2_5,c41_2_5);
    FA fa395(a23b18,a22b19,a21b20,s42_1_5,c42_1_5);
    FA fa396(s42_4,c41_1_4,c41_2_4,s42_2_5,c42_2_5);
    FA fa397(a23b19,a22b20,a21b21,s43_1_5,c43_1_5);
    FA fa398(a20b22,a19b23,c42_4,s43_2_5,c43_2_5);
    FA fa399(a22b21,a21b22,a20b23,s44_5,c44_5);

    // stage-6
    wire s4_6,c4_6,s5_6,c5_6,s6_6,c6_6,s7_6,c7_6,s8_6,c8_6,s9_6,c9_6,s10_6,c10_6,s11_6,c11_6,s12_6,c12_6;
    wire s13_6,c13_6,s14_6,c14_6,s15_6,c15_6,s16_6,c16_6,s17_6,c17_6;

    HA ha22(a1b2,a0b3,s4_6,c4_6);
    FA fa400(a3b1,a2b2,s5_5,s5_6,c5_6);
    FA fa401(s6_1_5,s6_2_5,c5_5,s6_6,c6_6);
    FA fa402(s7_2_5,c6_1_5,c6_2_5,s7_6,c7_6);
    FA fa403(s8_2_5,c7_1_5,c7_2_5,s8_6,c8_6);
    FA fa404(s9_2_5,c8_1_5,c8_2_5,s9_6,c9_6);
    FA fa405(s10_2_5,c9_1_5,c9_2_5,s10_6,c10_6);
    FA fa406(s11_2_5,c10_1_5,c10_2_5,s11_6,c11_6);
    FA fa407(s12_2_5,c11_1_5,c11_2_5,s12_6,c12_6);
    FA fa408(s13_2_5,c12_1_5,c12_2_5,s13_6,c13_6);
    FA fa409(s14_2_5,c13_1_5,c13_2_5,s14_6,c14_6);
    FA fa410(s15_2_5,c14_1_5,c14_2_5,s15_6,c15_6);
    FA fa411(s16_2_5,c15_1_5,c15_2_5,s16_6,c16_6);
    FA fa412(s17_2_5,c16_1_5,c16_2_5,s17_6,c17_6);

    wire s18_6,c18_6,s19_6,c19_6,s20_6,c20_6,s21_6,c21_6,s22_6,c22_6,s23_6,c23_6,s24_6,c24_6;
    wire s25_6,c25_6,s26_6,c26_6,s27_6,c27_6,s28_6,c28_6,s29_6,c29_6,s30_6,c30_6;

    FA fa413(s18_2_5,c17_1_5,c17_2_5,s18_6,c18_6);
    FA fa414(s19_2_5,c18_1_5,c18_2_5,s19_6,c19_6);
    FA fa415(s20_2_5,c19_1_5,c19_2_5,s20_6,c20_6);
    FA fa416(s21_2_5,c20_1_5,c20_2_5,s21_6,c21_6);
    FA fa417(s22_2_5,c21_1_5,c21_2_5,s22_6,c22_6);
    FA fa418(s23_2_5,c22_1_5,c22_2_5,s23_6,c23_6);
    FA fa419(s24_2_5,c23_1_5,c23_2_5,s24_6,c24_6);
    FA fa420(s25_2_5,c24_1_5,c24_2_5,s25_6,c25_6);
    FA fa421(s26_2_5,c25_1_5,c25_2_5,s26_6,c26_6);
    FA fa422(s27_2_5,c26_1_5,c26_2_5,s27_6,c27_6);
    FA fa423(s28_2_5,c27_1_5,c27_2_5,s28_6,c28_6);
    FA fa424(s29_2_5,c28_1_5,c28_2_5,s29_6,c29_6);
    FA fa425(s30_2_5,c29_1_5,c29_2_5,s30_6,c30_6);

    wire s31_6,c31_6,s32_6,c32_6,s33_6,c33_6,s34_6,c34_6,s35_6,c35_6,s36_6,c36_6;
    wire s37_6,c37_6,s38_6,c38_6,s39_6,c39_6,s40_6,c40_6,s41_6,c41_6,s42_6,c42_6;
    wire s43_6,c43_6,s44_6,c44_6,s45_6,c45_6;

    FA fa426(s31_2_5,c30_1_5,c30_2_5,s31_6,c31_6);
    FA fa427(s32_2_5,c31_1_5,c31_2_5,s32_6,c32_6);
    FA fa428(s33_2_5,c32_1_5,c32_2_5,s33_6,c33_6);
    FA fa429(s34_2_5,c33_1_5,c33_2_5,s34_6,c34_6);
    FA fa430(s35_2_5,c34_1_5,c34_2_5,s35_6,c35_6);
    FA fa431(s36_2_5,c35_1_5,c35_2_5,s36_6,c36_6);
    FA fa432(s37_2_5,c36_1_5,c36_2_5,s37_6,c37_6);
    FA fa433(s38_2_5,c37_1_5,c37_2_5,s38_6,c38_6);
    FA fa434(s39_2_5,c38_1_5,c38_2_5,s39_6,c39_6);
    FA fa435(s40_2_5,c39_1_5,c39_2_5,s40_6,c40_6);
    FA fa436(s41_2_5,c40_1_5,c40_2_5,s41_6,c41_6);
    FA fa437(s42_2_5,c41_1_5,c41_2_5,s42_6,c42_6);
    FA fa438(s43_2_5,c42_1_5,c42_2_5,s43_6,c43_6);
    FA fa439(s44_5,c43_1_5,c43_2_5,s44_6,c44_6);
    FA fa440(a22b22,a21b23,c44_5,s45_6,c45_6);

    // stage-7
    wire s2_7,c2_7,s3_7,c3_7,s4_7,c4_7,s5_7,c5_7,s6_7,c6_7,s7_7,c7_7,s8_7,c8_7,s9_7,c9_7;
    wire s10_7,c10_7,s11_7,c11_7,s12_7,c12_7,s13_7,c13_7,s14_7,c14_7,s15_7,c15_7,s16_7,c16_7;

    HA ha23(a1b0,a0b1,s2_7,c2_7);
    FA fa441(a2b0,a1b1,a0b2,s3_7,c3_7);
    FA fa442(a3b0,a2b1,s4_6,s4_7,c4_7);
    FA fa443(a4b0,s5_6,c4_6,s5_7,c5_7);
    FA fa444(a5b0,s6_6,c5_6,s6_7,c6_7);
    FA fa445(s7_1_5,s7_6,c6_6,s7_7,c7_7);
    FA fa446(s8_1_5,s8_6,c7_6,s8_7,c8_7);
    FA fa447(s9_1_5,s9_6,c8_6,s9_7,c9_7);
    FA fa448(s10_1_5,s10_6,c9_6,s10_7,c10_7);
    FA fa449(s11_1_5,s11_6,c10_6,s11_7,c11_7);
    FA fa450(s12_1_5,s12_6,c11_6,s12_7,c12_7);
    FA fa451(s13_1_5,s13_6,c12_6,s13_7,c13_7);
    FA fa452(s14_1_5,s14_6,c13_6,s14_7,c14_7);
    FA fa453(s15_1_5,s15_6,c14_6,s15_7,c15_7);
    FA fa454(s16_1_5,s16_6,c15_6,s16_7,c16_7);

    wire s17_7,c17_7,s18_7,c18_7,s19_7,c19_7,s20_7,c20_7,s21_7,c21_7,s22_7,c22_7;
    wire s23_7,c23_7,s24_7,c24_7,s25_7,c25_7,s26_7,c26_7,s27_7,c27_7;

    FA fa455(s17_1_5,s17_6,c16_6,s17_7,c17_7);
    FA fa456(s18_1_5,s18_6,c17_6,s18_7,c18_7);
    FA fa457(s19_1_5,s19_6,c18_6,s19_7,c19_7);
    FA fa458(s20_1_5,s20_6,c19_6,s20_7,c20_7);
    FA fa459(s21_1_5,s21_6,c20_6,s21_7,c21_7);
    FA fa460(s22_1_5,s22_6,c21_6,s22_7,c22_7);
    FA fa461(s23_1_5,s23_6,c22_6,s23_7,c23_7);
    FA fa462(s24_1_5,s24_6,c23_6,s24_7,c24_7);
    FA fa463(s25_1_5,s25_6,c24_6,s25_7,c25_7);
    FA fa464(s26_1_5,s26_6,c25_6,s26_7,c26_7);
    FA fa465(s27_1_5,s27_6,c26_6,s27_7,c27_7);

    wire s28_7,c28_7,s29_7,c29_7,s30_7,c30_7,s31_7,c31_7;
    wire s32_7,c32_7,s33_7,c33_7,s34_7,c34_7,s35_7,c35_7;
    wire s36_7,c36_7,s37_7,c37_7,s38_7,c38_7,s39_7,c39_7;
    wire s40_7,c40_7,s41_7,c41_7,s42_7,c42_7,s43_7,c43_7;

    FA fa466(s28_1_5,s28_6,c27_6,s28_7,c28_7);
    FA fa467(s29_1_5,s29_6,c28_6,s29_7,c29_7);
    FA fa468(s30_1_5,s30_6,c29_6,s30_7,c30_7);
    FA fa469(s31_1_5,s31_6,c30_6,s31_7,c31_7);
    FA fa470(s32_1_5,s32_6,c31_6,s32_7,c32_7);
    FA fa471(s33_1_5,s33_6,c32_6,s33_7,c33_7);
    FA fa472(s34_1_5,s34_6,c33_6,s34_7,c34_7);
    FA fa473(s35_1_5,s35_6,c34_6,s35_7,c35_7);
    FA fa474(s36_1_5,s36_6,c35_6,s36_7,c36_7);
    FA fa475(s37_1_5,s37_6,c36_6,s37_7,c37_7);
    FA fa476(s38_1_5,s38_6,c37_6,s38_7,c38_7);
    FA fa477(s39_1_5,s39_6,c38_6,s39_7,c39_7);
    FA fa478(s40_1_5,s40_6,c39_6,s40_7,c40_7);
    FA fa479(s41_1_5,s41_6,c40_6,s41_7,c41_7);
    FA fa480(s42_1_5,s42_6,c41_6,s42_7,c42_7);
    FA fa481(s43_1_5,s43_6,c42_6,s43_7,c43_7);

    wire s44_7,c44_7,s45_7,c45_7,s46_7,c46_7;

    FA fa482(a23b20,s44_6,c43_6,s44_7,c44_7);
    FA fa483(a23b21,s45_6,c44_6,s45_7,c45_7);
    FA fa484(a23b22,a22b23,c45_6,s46_7,c46_7);

    // stage-8: final carry-propagate ripple
    wire c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13,c14,c15;
    wire c16,c17,c18,c19,c20,c21,c22,c23,c24,c25,c26,c27,c28,c29,c30,c31,c32,c33,c34,c35,c36,c37,c38,c39,c40;
    wire c41,c42,c43,c44,c45,c46,c47;

    HA  ha24(s3_7,c2_7,prod[2],c3);
    FA fa485(s4_7,c3_7,c3,prod[3],c4);
    FA fa486(s5_7,c4_7,c4,prod[4],c5);
    FA fa487(s6_7,c5_7,c5,prod[5],c6);
    FA fa488(s7_7,c6_7,c6,prod[6],c7);
    FA fa489(s8_7,c7_7,c7,prod[7],c8);
    FA fa490(s9_7,c8_7,c8,prod[8],c9);
    FA fa491(s10_7,c9_7,c9,prod[9],c10);
    FA fa492(s11_7,c10_7,c10,prod[10],c11);
    FA fa493(s12_7,c11_7,c11,prod[11],c12);
    FA fa494(s13_7,c12_7,c12,prod[12],c13);
    FA fa495(s14_7,c13_7,c13,prod[13],c14);
    FA fa496(s15_7,c14_7,c14,prod[14],c15);
    FA fa497(s16_7,c15_7,c15,prod[15],c16);
    FA fa498(s17_7,c16_7,c16,prod[16],c17);
    FA fa499(s18_7,c17_7,c17,prod[17],c18);
    FA fa500(s19_7,c18_7,c18,prod[18],c19);
    FA fa501(s20_7,c19_7,c19,prod[19],c20);
    FA fa502(s21_7,c20_7,c20,prod[20],c21);
    FA fa503(s22_7,c21_7,c21,prod[21],c22);
    FA fa504(s23_7,c22_7,c22,prod[22],c23);
    FA fa505(s24_7,c23_7,c23,prod[23],c24);
    FA fa506(s25_7,c24_7,c24,prod[24],c25);
    FA fa507(s26_7,c25_7,c25,prod[25],c26);
    FA fa508(s27_7,c26_7,c26,prod[26],c27);
    FA fa509(s28_7,c27_7,c27,prod[27],c28);
    FA fa510(s29_7,c28_7,c28,prod[28],c29);
    FA fa511(s30_7,c29_7,c29,prod[29],c30);
    FA fa512(s31_7,c30_7,c30,prod[30],c31);
    FA fa513(s32_7,c31_7,c31,prod[31],c32);
    FA fa514(s33_7,c32_7,c32,prod[32],c33);
    FA fa515(s34_7,c33_7,c33,prod[33],c34);
    FA fa516(s35_7,c34_7,c34,prod[34],c35);
    FA fa517(s36_7,c35_7,c35,prod[35],c36);
    FA fa518(s37_7,c36_7,c36,prod[36],c37);
    FA fa519(s38_7,c37_7,c37,prod[37],c38);
    FA fa520(s39_7,c38_7,c38,prod[38],c39);
    FA fa521(s40_7,c39_7,c39,prod[39],c40);
    FA fa522(s41_7,c40_7,c40,prod[40],c41);
    FA fa523(s42_7,c41_7,c41,prod[41],c42);
    FA fa524(s43_7,c42_7,c42,prod[42],c43);
    FA fa525(s44_7,c43_7,c43,prod[43],c44);
    FA fa526(s45_7,c44_7,c44,prod[44],c45);
    FA fa527(s46_7,c45_7,c45,prod[45],c46);
    FA fa528(a23b23,c46_7,c46,prod[46],c47);

    assign prod[0]  = a0b0;
    assign prod[1]  = s2_7;
    assign prod[47] = c47;
endmodule


//=============================================================================
// mainMod - Top-Level IEEE 754 Dot Product  P = A*B + C*D
//
// PAPER: Sohn & Swartzlander, IEEE ARITH 2013 - Traditional design (Fig. 1)
//
// KEY FIX (this revision): Correct exponent formula.
//   final_exp = exp_product + (norm_shift - 46) + carry_out
//   where exp_product = max(expA+expB, expC+expD) - 127  [from expCompare]
//         norm_shift  = MSB position of the normalised significand sum
//         carry_out   = 1 if the sum+carry addition overflows bit 47
//   The constant 46 is the nominal MSB position for a 24x24-bit product
//   of two normalised IEEE 754 significands (both have implicit 1 at bit 23,
//   so product MSB is at bit 23+23=46 in the absence of overflow).
//=============================================================================
//=============================================================================
// mainMod - IEEE 754 Single-Precision Fused Dot Product
// Computes: P = A*B + C*D  (op=1) or  P = A*B - C*D  (op=0)
//
// Architecture (Traditional design from Sohn & Swartzlander, IEEE ARITH 2013):
//   1.  Unpack sign / biased-exponent / significand from each operand
//   2.  Two 24x24 Dadda multipliers produce 48-bit integer products
//   3.  Compute real product exponents:  eAB = expA+expB-127, eCD = expC+expD-127
//   4.  Determine effective operation (add or subtract significands)
//   5.  Select larger/smaller product; align smaller by right-shifting
//   6.  Add or subtract the two aligned 48-bit significands (with 2's complement)
//   7.  Normalise result: find MSB, shift to bit 47
//   8.  Compute final exponent:  final_exp = max_exp + (msb_pos - 46) + overflow
//   9.  Round to 23 mantissa bits
//  10.  Assemble IEEE 754 output; handle special cases
//
// Note on exponent constant 46:
//   Both Dadda inputs are 24-bit significands with implicit leading 1.
//   Their product has its MSB at bit 23+23 = 46 (no overflow case).
//   If the product mantissas are large enough to overflow to bit 47, the
//   MSB position becomes 47, and the exponent adjustment handles that.
//=============================================================================
//=============================================================================
// mainMod - IEEE 754 Single-Precision Fused Dot Product
// Computes: P = A*B + C*D  (op=1)  or  P = A*B - C*D  (op=0)
//=============================================================================
//=============================================================================
// mainMod - IEEE 754 Single-Precision Fused Dot Product
// Computes: P = A*B + C*D  (op=1)  or  P = A*B - C*D  (op=0)
//=============================================================================
module mainMod(A, B, C, D, op, out, rnd_mode);
    input  [31:0] A, B, C, D;
    input         op;
    input  [1:0]  rnd_mode;
    output reg [31:0] out;

    // ── 1. Unpack ──────────────────────────────────────────────────────────
    wire [7:0]  expA=A[30:23]; wire [7:0]  expB=B[30:23];
    wire [7:0]  expC=C[30:23]; wire [7:0]  expD=D[30:23];
    wire [22:0] fracA=A[22:0]; wire [22:0] fracB=B[22:0];
    wire [22:0] fracC=C[22:0]; wire [22:0] fracD=D[22:0];
    wire [23:0] sigA={1'b1,fracA}; wire [23:0] sigB={1'b1,fracB};
    wire [23:0] sigC={1'b1,fracC}; wire [23:0] sigD={1'b1,fracD};

    // ── Special cases ──────────────────────────────────────────────────────
    wire A_zer=(expA==8'd0); wire B_zer=(expB==8'd0);
    wire C_zer=(expC==8'd0); wire D_zer=(expD==8'd0);
    wire A_inf=(expA==8'hFF)&(fracA==0); wire B_inf=(expB==8'hFF)&(fracB==0);
    wire C_inf=(expC==8'hFF)&(fracC==0); wire D_inf=(expD==8'hFF)&(fracD==0);
    wire A_nan=(expA==8'hFF)&(fracA!=0); wire B_nan=(expB==8'hFF)&(fracB!=0);
    wire C_nan=(expC==8'hFF)&(fracC!=0); wire D_nan=(expD==8'hFF)&(fracD!=0);
    wire any_nan = A_nan|B_nan|C_nan|D_nan;
    wire ab_inf_zero = (A_inf&B_zer)|(B_inf&A_zer);
    wire cd_inf_zero = (C_inf&D_zer)|(D_inf&C_zer);
    wire inf_times_zero = ab_inf_zero|cd_inf_zero;
    wire any_inf = (A_inf&~B_zer&~ab_inf_zero)|(B_inf&~A_zer&~ab_inf_zero)
                 |(C_inf&~D_zer&~cd_inf_zero)|(D_inf&~C_zer&~cd_inf_zero);
    wire ab_zero = A_zer|B_zer;
    wire cd_zero = C_zer|D_zer;

    // ── 2. Multiply ────────────────────────────────────────────────────────
    wire [47:0] multAB, multCD;
    dadda d1(sigA, sigB, multAB);
    dadda d2(sigC, sigD, multCD);

    // ── 3. Real product exponents ─────────────────────────────────────────
    // BUGFIX: When one operand pair is zero (exp==0), the raw subtraction
    // 0+0-127 wraps to +385 in unsigned 9-bit, which incorrectly appears
    // LARGER than a valid exponent. Clamp to -255 (9'b1_0000_0001) so the
    // zero product always loses the exponent comparison and gets shifted out.
    wire [8:0] eAB_raw = {1'b0,expA} + {1'b0,expB} - 9'd127;
    wire [8:0] eCD_raw = {1'b0,expC} + {1'b0,expD} - 9'd127;
    wire [8:0] eAB = ab_zero ? 9'b1_0000_0001 : eAB_raw;  // clamp if AB=0
    wire [8:0] eCD = cd_zero ? 9'b1_0000_0001 : eCD_raw;  // clamp if CD=0

    // ── 4. Signs of products ───────────────────────────────────────────────
    wire sign_AB = A[31] ^ B[31];
    wire sign_CD = C[31] ^ D[31];

    // ── 5. Compare magnitudes: exponent first, then significand ───────────
    // When eAB > eCD: AB is unambiguously larger.
    // When eAB < eCD: CD is unambiguously larger.
    // When eAB == eCD: compare the 48-bit product magnitudes directly.
    // exp_comp=1 means AB magnitude >= CD magnitude (AB is large, CD is small).
    // Use signed comparison - eAB/eCD can be negative (e.g. 0.0→-255 after clamp)
    wire exp_eq    = ($signed(eAB) == $signed(eCD));
    wire exp_gt    = ($signed(eAB) >  $signed(eCD));
    wire sig_ge    = (multAB >= multCD);   // significand comparison when exps equal
    wire exp_comp  = exp_gt | (exp_eq & sig_ge);

    wire [8:0] exp_large = exp_comp ? eAB : eCD;
    // exp_diff: how many bits to right-shift the smaller product.
    // When one product is clamped to -255, diff is large → aligned product = 0
    wire [8:0] exp_diff9 = $signed(exp_large) - $signed(exp_comp ? eCD : eAB);
    wire [7:0] exp_diff  = exp_diff9[7:0];  // saturates at 255 - enough for 48-bit shift

    wire [47:0] large_sig  = exp_comp ? multAB : multCD;
    wire [47:0] small_sig  = exp_comp ? multCD  : multAB;
    wire        sign_large = exp_comp ? sign_AB : sign_CD;

    // ── 6. Effective operation ─────────────────────────────────────────────
    wire op_sel;
    opSelect op1(A[31],B[31],C[31],D[31], op, op_sel);

    // ── 7. Align smaller product ───────────────────────────────────────────
    wire guard1, round1, sticky1;
    wire [47:0] small_aligned;
    shifter_48b sh1(exp_diff, small_sig, guard1, round1, sticky1, small_aligned);

    // ── 8. Add or subtract significand magnitudes ─────────────────────────
    wire [48:0] sig_sum_raw;
    assign sig_sum_raw = op_sel ? ({1'b0,large_sig} - {1'b0,small_aligned})
                                : ({1'b0,large_sig} + {1'b0,small_aligned});

    // ── 9. Result sign ────────────────────────────────────────────────────
    // sign = sign_large XOR (~exp_comp & ~op)
    // When exp_comp=0 (CD is large) AND op=0 (subtract):
    //   we computed CD_mag - AB_mag (positive), but real result = AB - CD = -(CD-AB)
    //   so negate the sign_large.
    wire sign;
    assign sign = sign_large ^ (~exp_comp & ~op);

    // ── 10. Normalise ─────────────────────────────────────────────────────
    wire       overflow48 = sig_sum_raw[48];
    wire [7:0] norm_shift_bits;
    leadOne l1(sig_sum_raw[47:0], norm_shift_bits);
    wire [7:0] msb_pos = overflow48 ? 8'd48 : norm_shift_bits;

    wire [47:0] norm_sig;
    assign norm_sig = overflow48
                      ? sig_sum_raw[48:1]
                      : (sig_sum_raw[47:0] << (7'd47 - norm_shift_bits));

    // ── 11. Exponent ──────────────────────────────────────────────────────
    wire [8:0] final_exp_9 = exp_large + {1'b0,msb_pos} - 9'd46;
    wire [7:0] final_exp   = final_exp_9[7:0];

    // ── 12. Rounding bits ─────────────────────────────────────────────────
    wire lsb_r   = norm_sig[24];
    wire guard_r = norm_sig[23];
    wire round_r = norm_sig[22];
    wire sticky_r = |norm_sig[21:0] | sticky1 | round1 | guard1;

    // ── 13. Round ─────────────────────────────────────────────────────────
    wire rnd_up;
    stickyRound st1(sign, lsb_r, guard_r, round_r, sticky_r, rnd_mode, rnd_up);

    // ── 14. Apply rounding increment ──────────────────────────────────────
    // FIX: add 1 at bit 24 (= 1 ULP in the 23-bit mantissa field),
    // NOT at bit 0. Adding 48'd1 only affects bits below the mantissa.
    wire [47:0] rounded = rnd_up ? (norm_sig + 48'h1000000) : norm_sig;

    // ── 15. Mantissa ──────────────────────────────────────────────────────
    wire [22:0] mantissa_out = rounded[46:24];

    // ── 16. Output ────────────────────────────────────────────────────────
    wire result_zero = (sig_sum_raw == 49'd0);
    always @(*) begin
        if (any_nan | inf_times_zero)
            out = 32'h7FC00000;
        else if (any_inf)
            out = {sign_large, 8'hFF, 23'd0};
        else if ((ab_zero & cd_zero) | result_zero)
            out = 32'h00000000;
        else
            out = {sign, final_exp, mantissa_out};
    end
endmodule