/* ********************************************
 *	COSE222 Lab #4
 *
 *	Module: pipelined_cpu.sv
 *  - Top design of the 5-stage pipelined RISC-V processor
 *  - Processor supports ld, sd, add, sub, or, and, beq, bne, blt, bge
 *
 *  Author: Gunjae Koo (gunjaekoo@korea.ac.kr)
 *
 * ********************************************
 */

`timescale 1ns/1ps

// Packed structures for pipeline registers
// COMPLETE THE PIPELINE INTERFACES USING PACKED STRUCTURES
// Pipe reg: IF/ID
typedef struct packed {
    logic   [31:0]  pc;
    logic   [31:0]  inst;
} pipe_if_id;

// Pipe reg: ID/EX
typedef struct packed {
    logic   [31:0]  pc;
    logic   [31:0]  rs1_dout;
    logic   [31:0]  rs2_dout;
    logic   [31:0]  imm32;
    logic   [2:0]   funct3;
    logic   [6:0]   funct7;
    logic   [5:0]   branch;     // [0]beq [1]bne [2]blt [3]bge [4]bltu [5]bgeu
    logic           alu_src;
    logic   [1:0]   alu_op;
    logic           mem_read;
    logic           mem_write;
    logic   [4:0]   rs1;
    logic   [4:0]   rs2;
    logic   [4:0]   rd;         // rd for regfile
    logic           reg_write;
    logic           mem_to_reg;
    logic           lui;
    logic           auipc;
    logic           jal;
    logic           jalr;
} pipe_id_ex;

// Pipe reg: EX/MEM
typedef struct packed {
    logic   [31:0]  alu_result; // for address
    logic   [31:0]  rs2_dout;   // for store
    logic   [2:0]   funct3;
    logic           mem_read;
    logic           mem_write;
    logic   [4:0]   rd;
    logic           reg_write;
    logic           mem_to_reg;
} pipe_ex_mem;

// Pipe reg: MEM/WB
typedef struct packed {
    logic   [31:0]  alu_result;
    logic   [31:0]  dmem_dout;
    logic   [4:0]   rd;
    logic           reg_write;
    logic           mem_to_reg;
} pipe_mem_wb;

/* verilator lint_off UNUSED */
module pipeline_cpu
#(  parameter IMEM_DEPTH = 1024,    // imem depth (default: 1024 entries = 4 KB)
              IMEM_ADDR_WIDTH = 10,
              REG_WIDTH = 32,
              DMEM_DEPTH = 1024,    // dmem depth (default: 1024 entries = 8 KB)
              DMEM_ADDR_WIDTH = 12 )
(
    input           clk,            // System clock
    input           reset_b         // Asychronous negative reset
);

    // -------------------------------------------------------------------
    /* Instruction fetch stage:
     * - Accessing the instruction memory with PC
     * - Control PC udpates for pipeline stalls
     */

    // Program counter
    logic           pc_write;   // enable PC updates
    logic   [31:0]  pc_curr, pc_next;
    logic   [31:0]  pc_next_plus4, pc_next_branch;
    logic   [31:0]  pc_target;
    logic           pc_next_sel;
    logic           branch_taken;
    //logic           regfile_zero;   // zero detection from regfile, REMOVED

    assign pc_next_plus4 = pc_curr + 4;
    assign pc_next = (pc_next_sel) ? pc_target: pc_next_plus4;

    always_ff @ (posedge clk or negedge reset_b) begin
        if (~reset_b) begin
            pc_curr <= 'b0;
        end else begin
            if (pc_write)
                pc_curr <= pc_next;
        end
    end

    // imem
    logic   [IMEM_ADDR_WIDTH-1:0]   imem_addr;
    logic   [31:0]  inst;   // instructions = an output of ????
    
    assign imem_addr = pc_curr[IMEM_ADDR_WIDTH+1:2];

    // instantiation: instruction memory
    imem #(
        .IMEM_DEPTH         (IMEM_DEPTH),
        .IMEM_ADDR_WIDTH    (IMEM_ADDR_WIDTH)
    ) u_imem_0 (
        .addr               ( imem_addr     ),
        .dout               ( inst          )
    );
    // -------------------------------------------------------------------

    // -------------------------------------------------------------------
    /* IF/ID pipeline register
     * - Supporting pipeline stalls and flush
     */
    pipe_if_id      id;         // THINK WHY THIS IS ID...
    pipe_id_ex      ex;
    pipe_ex_mem     mem;
    pipe_mem_wb     wb;

    logic           if_flush, if_stall;

    always_ff @ (posedge clk or negedge reset_b) begin
        if (~reset_b) begin
            id <= 'b0;
        end else begin
            if (if_flush) begin
                id <= 'b0;
            end else if (~if_stall) begin
                id.pc <= pc_curr; 
                id.inst <= inst; 
            end
        end
    end
    // -------------------------------------------------------------------

    // ------------------------------------------------------------------
    /* Instruction decoder stage:
     * - Generating control signals
     * - Register file
     * - Immediate generator
     * - Hazard detection unit
     */
    
    // -------------------------------------------------------------------
    /* Main control unit:
     * Main control unit generates control signals for datapath elements
     * The control signals are determined by decoding instructions
     * Generating control signals using opcode = inst[6:0]
     */
    logic   [6:0]   opcode;
    logic   [5:0]   branch;
    logic           alu_src, mem_to_reg;
    logic   [1:0]   alu_op;
    logic           mem_read, mem_write, reg_write; // declared above
    logic   [6:0]   funct7;
    logic   [2:0]   funct3;
    logic           lui, auipc;
    logic           jal, jalr;

    // COMPLETE THE MAIN CONTROL UNIT HERE
    assign opcode = id.inst[6:0];
    assign funct3 = id.inst[14:12];
    assign funct7 = id.inst[31:25];
    
    assign branch[0] = ((opcode==7'b1100011) && (funct3==3'b000)) ? 1'b1: 1'b0;  // beq
    assign branch[1] = ((opcode==7'b1100011) && (funct3==3'b001)) ? 1'b1: 1'b0;  // bne
    assign branch[2] = ((opcode==7'b1100011) && (funct3==3'b100)) ? 1'b1: 1'b0;  // blt
    assign branch[3] = ((opcode==7'b1100011) && (funct3==3'b101)) ? 1'b1: 1'b0;  // bge
    assign branch[4] = ((opcode==7'b1100011) && (funct3==3'b110)) ? 1'b1: 1'b0;  // bltu
    assign branch[5] = ((opcode==7'b1100011) && (funct3==3'b111)) ? 1'b1: 1'b0;  // bgeu

    assign lui   = (opcode==7'b0110111) ? 1'b1: 1'b0;   // lui
    assign auipc = (opcode==7'b0010111) ? 1'b1: 1'b0;   // auipc
    assign jal   = (opcode==7'b1101111) ? 1'b1: 1'b0;   // jal
    assign jalr  = (opcode==7'b1100111) ? 1'b1: 1'b0;   // jalr

    assign mem_read = (opcode==7'b0000011) ? 1'b1: 1'b0;    // ld
    assign mem_write = (opcode==7'b0100011) ? 1'b1: 1'b0;   // sd
    assign mem_to_reg = mem_read;
    assign reg_write = (opcode==7'b0110011) | (opcode==7'b0010011) | mem_read | lui | auipc | jal | jalr;   // ld, r-type, i-type, lui, auipc, jal, jalr
    assign alu_src = ( mem_read | mem_write | (opcode==7'b0010011) | lui | auipc ) ? 1'b1: 1'b0;   // ld, sd, i-type, lui, auipc

    assign alu_op[0] = |branch;                                         // branch -> 01
    assign alu_op[1] = (opcode==7'b0110011) | (opcode==7'b0010011);     // r-type/i-type -> 10

    // --------------------------------------------------------------------

    // ---------------------------------------------------------------------
    /* Immediate generator:
     * Generating immediate value from inst[31:0]
     */
    logic   [31:0]  imm32;
    logic   [31:0]  imm32_branch;  // imm64 left shifted by 1

    // COMPLETE IMMEDIATE GENERATOR HERE
    logic   [11:0]  imm12;

    assign imm12 = (opcode == 7'b0100011) ? {id.inst[31:25], id.inst[11:7]} :                          // S-type
                   (opcode == 7'b1100011) ? {id.inst[31], id.inst[7], id.inst[30:25], id.inst[11:8]} : // B-type
                   id.inst[31:20];                                                                     // I-type (default)
    assign imm32 = (lui | auipc) ? {id.inst[31:12], 12'b0} :     // U-type (already <<12)
                   (jal)         ? {{12{id.inst[31]}}, id.inst[19:12], id.inst[20], id.inst[30:21], 1'b0} : // J-type (byte offset)
                                   {{20{imm12[11]}}, imm12};      // I/S/B-type (jalr = I-type)
    assign imm32_branch = imm32 << 1;

    // Computing branch target
    assign pc_next_branch = ex.pc + (ex.imm32 << 1); 

    // ----------------------------------------------------------------------

    // ----------------------------------------------------------------------
    /* Hazard detection unit
     * - Detecting data hazards from load instrcutions
     * - Detecting control hazards from taken branches
     */
    logic   [4:0]   rs1, rs2;

    logic           stall_by_load_use;
    logic           flush_by_branch;
    
    logic           id_stall, id_flush;


    assign stall_by_load_use = ex.mem_read & ((ex.rd == rs1) | (ex.rd == rs2)) & (|ex.rd);
    assign flush_by_branch = branch_taken | ex.jal | ex.jalr;
  
    assign id_flush = stall_by_load_use | flush_by_branch;
    assign id_stall = 1'b0;
	
    assign if_flush = flush_by_branch;
    assign if_stall = stall_by_load_use;
    assign pc_write = ~stall_by_load_use;

    // ----------------------------------------------------------------------


    // regfile/
    logic   [4:0]   rd;    // register numbers
    logic   [REG_WIDTH-1:0] rd_din;
    logic   [REG_WIDTH-1:0] rs1_dout, rs2_dout;
    
    assign rs1 = id.inst[19:15];     // our processor does NOT support U and UJ types
    assign rs2 = id.inst[24:20];     // consider ld and i-type
    assign rd = id.inst[11:7]; 
    // rd, rd_din, and reg_write will be determined in WB stage
    
    // instnatiation of register file
    regfile #(
        .REG_WIDTH          (REG_WIDTH)
    ) u_regfile_0 (
        .clk                (clk),
        .rs1                (rs1),
        .rs2                (rs2),
        .rd                 (wb.rd),
        .rd_din             (rd_din),
        .reg_write          (wb.reg_write),
        .rs1_dout           (rs1_dout),
        .rs2_dout           (rs2_dout)
    );

    //assign regfile_zero = ~|(rs1_dout ^ rs2_dout); // REMOVED

    // ------------------------------------------------------------------

    // -------------------------------------------------------------------
    /* ID/EX pipeline register
     * - Supporting pipeline stalls
     */
    //pipe_id_ex      ex;         // THINK WHY THIS IS EX...

    always_ff @ (posedge clk or negedge reset_b) begin
        if (~reset_b) begin
            ex <= 'b0;
        end else begin
            if (id_flush) begin
                ex <= 'b0;
            end else if (~id_stall) begin
                ex.pc <= id.pc;
                ex.rs1_dout <= rs1_dout;
                ex.rs2_dout <= rs2_dout;
                ex.imm32 <= imm32;
                ex.funct3 <= funct3;
                ex.funct7 <= funct7;
                ex.branch <= branch;
                ex.alu_src <= alu_src;
                ex.alu_op <= alu_op;
                ex.mem_read <= mem_read;
                ex.mem_write <= mem_write;
                ex.rs1 <= rs1;
                ex.rs2 <= rs2;
                ex.rd  <= rd;
                ex.reg_write <= reg_write;
                ex.mem_to_reg <= mem_to_reg;
                ex.lui <= lui;
                ex.auipc <= auipc;
                ex.jal <= jal;
                ex.jalr <= jalr;
            end
        end
    end


    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    /* Excution stage:
     * - ALU & ALU control
     * - Data forwarding unit
     */

    // --------------------------------------------------------------------
    /* ALU control unit:
     * ALU control unit generate alu_control signal which selects ALU operations
     * Generating control signals using alu_op, funct7, and funct3 fileds
     */

    logic   [3:0]   alu_control;    // ALU control signal

    // COMPLETE ALU CONTROL UNIT
	
    always_comb begin
        if (ex.alu_op[1]) begin     // R-type / I-type 연산
            case (ex.funct3)
                3'b000: alu_control = (~ex.alu_src & ex.funct7[5]) ? 4'b0110 : 4'b0010; // SUB/ADD
                3'b001: alu_control = 4'b0100;           // SLL / SLLI
                3'b010: alu_control = 4'b1000;           // SLT / SLTI
                3'b011: alu_control = 4'b1001;           // SLTU / SLTIU
                3'b100: alu_control = 4'b0011;           // XOR / XORI
                3'b101: alu_control = (ex.funct7[5]) ? 4'b0111 : 4'b0101; // SRA/SRL (SRAI/SRLI)
                3'b110: alu_control = 4'b0001;           // OR / ORI
                3'b111: alu_control = 4'b0000;           // AND / ANDI
            endcase
        end else begin
            alu_control = (ex.alu_op[0]) ? 4'b0110 : 4'b0010;   // branch=SUB, load/store=ADD
        end
    end
	
    // ---------------------------------------------------------------------

    // ----------------------------------------------------------------------
    /* Forwarding unit:
     * - Forwarding from EX/MEM and MEM/WB
     */
    logic   [1:0]   forward_a, forward_b;
    logic   [REG_WIDTH-1:0]  alu_fwd_in1, alu_fwd_in2;   // outputs of forward MUXes

	/* verilator lint_off CASEX */
    // COMPLETE FORWARDING MUXES
    assign alu_fwd_in1 = (forward_a == 2'b10) ? mem.alu_result :
                         (forward_a == 2'b01) ? rd_din :
                         ex.rs1_dout;

    assign alu_fwd_in2 = (forward_b == 2'b10) ? mem.alu_result :
                         (forward_b == 2'b01) ? rd_din :
                         ex.rs2_dout;
   
   
	/* verilator lint_on CASEX */
	// COMPLETE THE FORWARDING UNIT
    // Need to prioritize forwarding conditions
    always_comb begin
        // forward_a (rs1)
        if (mem.reg_write && (mem.rd != 5'b0) && (mem.rd == ex.rs1))
            forward_a = 2'b10;
        else if (wb.reg_write && (wb.rd != 5'b0) && (wb.rd == ex.rs1))
            forward_a = 2'b01;
        else
            forward_a = 2'b00;

        // forward_b (rs2)
        if (mem.reg_write && (mem.rd != 5'b0) && (mem.rd == ex.rs2))
            forward_b = 2'b10;
        else if (wb.reg_write && (wb.rd != 5'b0) && (wb.rd == ex.rs2))
            forward_b = 2'b01;
        else
            forward_b = 2'b00;
    end


    // -----------------------------------------------------------------------

    // ALU
    logic   [REG_WIDTH-1:0] alu_in1, alu_in2;
    logic   [REG_WIDTH-1:0] alu_result;
    //logic           alu_zero;   // will not be used

    assign alu_in1 = (ex.auipc) ? ex.pc :
                     (ex.lui)   ? 32'b0 :
                                  alu_fwd_in1;
    assign alu_in2 = (ex.alu_src) ? ex.imm32 : alu_fwd_in2;

    // instantiation: ALU
    alu #(
        .REG_WIDTH          (REG_WIDTH)
    ) u_alu_0 (
        .in1                (alu_in1),
        .in2                (alu_in2),
        .alu_control        (alu_control),
        .result             (alu_result)
        //.zero             (alu_zero),	    // REMOVED
		//.sign				(alu_sign)		// REMOVED
    );

    // branch unit (BU)
    logic   [REG_WIDTH-1:0] sub_for_branch;
    logic           bu_zero, bu_sign, bu_sign_u;
    //logic           branch_taken;

    assign sub_for_branch = alu_fwd_in1 - alu_fwd_in2;
    assign bu_zero = ~|sub_for_branch;
    assign bu_sign = sub_for_branch[31];
    assign bu_sign_u = (alu_fwd_in1 < alu_fwd_in2);
    assign branch_taken = ex.branch[0] & bu_zero              // beq
                        | ex.branch[1] & ~bu_zero             // bne
                        | ex.branch[2] & bu_sign              // blt
                        | ex.branch[3] & ~bu_sign             // bge
                        | ex.branch[4] & bu_sign_u            // bltu
                        | ex.branch[5] & ~bu_sign_u;          // bgeu

    assign pc_next_sel = branch_taken | ex.jal | ex.jalr;
    assign pc_target = (ex.jalr) ? ((alu_fwd_in1 + ex.imm32) & ~32'b1) :
                       (ex.jal)  ? (ex.pc + ex.imm32) :
                                   pc_next_branch;

    // -------------------------------------------------------------------------
    /* Ex/MEM pipeline register
     */
    //pipe_ex_mem     mem;

    always_ff @ (posedge clk or negedge reset_b) begin
        if (~reset_b) begin
            mem <= 'b0;
        end else begin
            mem.alu_result <= (ex.jal | ex.jalr) ? (ex.pc + 32'd4) : alu_result;
            mem.rs2_dout <= alu_fwd_in2;
            mem.funct3 <= ex.funct3;
            mem.mem_read <= ex.mem_read;
            mem.mem_write <= ex.mem_write;
            mem.rd <= ex.rd;
            mem.reg_write <= ex.reg_write;
            mem.mem_to_reg <= ex.mem_to_reg;
        end
    end


    // --------------------------------------------------------------------------
    /* Memory srage
     * - Data memory accesses
     */

    // dmem
    logic   [DMEM_ADDR_WIDTH-1:0]    dmem_addr;
    logic   [31:0]  dmem_din, dmem_dout;
    logic [1:0] sz;

    assign sz = mem.funct3[1:0];   // 00=byte, 01=half, 10=word
    assign dmem_addr = mem.alu_result[DMEM_ADDR_WIDTH-1:0];
    assign dmem_din = mem.rs2_dout; 
    
    // instantiation: data memory
    dmem #(
        .DMEM_DEPTH         (DMEM_DEPTH),
        .DMEM_ADDR_WIDTH    (DMEM_ADDR_WIDTH)
    ) u_dmem_0 (
        .clk                (clk),
        .addr               (dmem_addr),
        .din                (dmem_din),
        .rd_en              (mem.mem_read),
        .wr_en              (mem.mem_write),
        .sz                 (sz),
        .dout               (dmem_dout)
    );

    logic   [31:0]  load_ext;
    always_comb begin
        case (mem.funct3)
            3'b000: load_ext = {{24{dmem_dout[7]}},  dmem_dout[7:0]};    // LB
            3'b001: load_ext = {{16{dmem_dout[15]}}, dmem_dout[15:0]};   // LH
            3'b100: load_ext = {24'b0, dmem_dout[7:0]};                  // LBU
            3'b101: load_ext = {16'b0, dmem_dout[15:0]};                 // LHU
            default: load_ext = dmem_dout;                              // LW
        endcase
    end


    // -----------------------------------------------------------------------
    /* MEM/WB pipeline register
     */

    //pipe_mem_wb         wb;

    always_ff @ (posedge clk or negedge reset_b) begin
        if (~reset_b) begin
            wb <= 'b0;
        end else begin
            wb.alu_result <= mem.alu_result;
            wb.dmem_dout <= load_ext;
            wb.rd <= mem.rd;
            wb.reg_write <= mem.reg_write;
            wb.mem_to_reg <= mem.mem_to_reg;
        end
    end

    // ----------------------------------------------------------------------
    /* Writeback stage
     * - Write results to regsiter file
     */
    
    assign rd_din = wb.mem_to_reg ? wb.dmem_dout : wb.alu_result;

endmodule
