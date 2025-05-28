module RISCV_Pipeline (
    input wire clock,
    input wire reset
);
  integer i;
  //===============================
  // Memória de instruções e dados
  //===============================
  reg [31:0] instr_mem [0:15];  // 16 instruções
  reg [15:0] data_mem  [0:255]; // memória de dados
  reg [15:0] regfile   [0:31];  // 32 registradores

  //=======================
  // Registradores pipeline
  //=======================
  // IF/ID
  reg [31:0] IF_ID_instr;
  reg [31:0] IF_ID_PC;

  // ID/EX
  reg [15:0] ID_EX_rs1_data, ID_EX_rs2_data;
  reg [15:0] ID_EX_imm;
  reg [4:0]  ID_EX_rs1, ID_EX_rs2, ID_EX_rd;
  reg [6:0]  ID_EX_opcode;
  reg [2:0]  ID_EX_funct3;
  reg [6:0]  ID_EX_funct7;

  // EX/MEM
  reg [15:0] EX_MEM_alu_result, EX_MEM_rs2_data;
  reg [4:0]  EX_MEM_rd;
  reg [6:0]  EX_MEM_opcode;

  // MEM/WB
  reg [15:0] MEM_WB_data;
  reg [4:0]  MEM_WB_rd;
  reg [6:0]  MEM_WB_opcode;

  //=====================
  // Contador de programa
  //=====================
  reg [31:0] PC;

  //=====================
  // Inicialização
  //=====================
  initial begin
    PC = 0;

    // instruções:
    // addi x1, x0, 5     ; x1 = 5
    // addi x2, x0, 10    ; x2 = 10
    // add  x3, x1, x2    ; x3 = x1 + x2 = 15
    // sub  x4, x2, x1    ; x4 = x2 - x1 = 5
    // sw   x3, 0(x0)     ; mem[0] = x3 = 15
    // lw   x5, 0(x0)     ; x5 = mem[0] = 15

    // 0: addi x1, x0,  5       ; x1 =  5
    instr_mem[0]  = {12'd5,  5'd0, 3'b000, 5'd1, 7'b0010011};

    // 1: addi x2, x0, 10       ; x2 = 10
    instr_mem[1]  = {12'd10, 5'd0, 3'b000, 5'd2, 7'b0010011};

    // 2–4: NOPs (aguarda x1 e x2 serem escritos)
    instr_mem[2]  = 32'b0;
    instr_mem[3]  = 32'b0;
    instr_mem[4]  = 32'b0;

    // 5: add  x3, x1, x2       ; x3 = x1 + x2 = 15
    instr_mem[5]  = {7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011};

    // 6: sub  x4, x2, x1       ; x4 = x2 - x1 =  5
    instr_mem[6]  = {7'b0100000, 5'd1, 5'd2, 3'b000, 5'd4, 7'b0110011};

    // 7–8: NOPs (aguarda x3 ser escrito)
    instr_mem[7]  = 32'b0;
    instr_mem[8]  = 32'b0;

    // 9: sw   x3, 0(x0)        ; mem[0] = x3 = 15
    instr_mem[9]  = {7'b0000000, 5'd3, 5'd0, 3'b010, 5'd0, 7'b0100011};

    // 10: lw   x5, 0(x0)       ; x5 = mem[0] = 15
    instr_mem[10] = {12'd0, 5'd0, 3'b010, 5'd5, 7'b0000011};

    // 11–15: NOPs ou instruções livres
    instr_mem[11] = 32'b0;
    instr_mem[12] = 32'b0;
    instr_mem[13] = 32'b0;
    instr_mem[14] = 32'b0;
    instr_mem[15] = 32'b0;



    // limpa banco de registradores e mem
    for (i = 0; i < 32; i = i + 1) regfile[i] = 0;
    for (i = 0; i < 256; i = i + 1) data_mem[i] = 0;
  end

  //====================
  // Estágio IF
  //====================
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      PC <= 0;
      IF_ID_instr <= 0;
      IF_ID_PC <= 0;
    end else begin
      IF_ID_instr <= instr_mem[PC >> 2];
      IF_ID_PC <= PC;
      PC <= PC + 4;
    end
  end

  //====================
  // Estágio ID
  //====================
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      ID_EX_rs1_data <= 0;
      ID_EX_rs2_data <= 0;
      ID_EX_imm      <= 0;
      ID_EX_rs1      <= 0;
      ID_EX_rs2      <= 0;
      ID_EX_rd       <= 0;
      ID_EX_opcode   <= 0;
      ID_EX_funct3   <= 0;
      ID_EX_funct7   <= 0;
    end else begin
      ID_EX_opcode   <= IF_ID_instr[6:0];
      ID_EX_rd       <= IF_ID_instr[11:7];
      ID_EX_funct3   <= IF_ID_instr[14:12];
      ID_EX_rs1      <= IF_ID_instr[19:15];
      ID_EX_rs2      <= IF_ID_instr[24:20];
      ID_EX_funct7   <= IF_ID_instr[31:25];

      ID_EX_rs1_data <= regfile[IF_ID_instr[19:15]];
      ID_EX_rs2_data <= regfile[IF_ID_instr[24:20]];

      // Imediato para I, S
      if (IF_ID_instr[6:0] == 7'b0010011 || IF_ID_instr[6:0] == 7'b0000011) begin
        ID_EX_imm <= {{4{IF_ID_instr[31]}}, IF_ID_instr[31:20]};
      end else if (IF_ID_instr[6:0] == 7'b0100011) begin
        ID_EX_imm <= {{4{IF_ID_instr[31]}}, IF_ID_instr[31:25], IF_ID_instr[11:7]};
      end else begin
        ID_EX_imm <= 0;
      end
    end
  end

  //====================
  // Estágio EX
  //====================
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      EX_MEM_alu_result <= 0;
      EX_MEM_rd         <= 0;
      EX_MEM_rs2_data   <= 0;
      EX_MEM_opcode     <= 0;
    end else begin
      EX_MEM_opcode     <= ID_EX_opcode;
      EX_MEM_rd         <= ID_EX_rd;
      EX_MEM_rs2_data   <= ID_EX_rs2_data;

      case (ID_EX_opcode)
        7'b0110011: begin // R-type (add, sub)
          if (ID_EX_funct7 == 7'b0100000)
            EX_MEM_alu_result <= ID_EX_rs1_data - ID_EX_rs2_data; // sub
          else
            EX_MEM_alu_result <= ID_EX_rs1_data + ID_EX_rs2_data; // add
        end
        7'b0010011: begin // addi
          EX_MEM_alu_result <= ID_EX_rs1_data + ID_EX_imm;
        end
        7'b0000011,        // lw
        7'b0100011: begin  // sw
          EX_MEM_alu_result <= ID_EX_rs1_data + ID_EX_imm; // endereço
        end
        default: EX_MEM_alu_result <= 0;
      endcase
    end
  end

  //====================
  // Estágio MEM
  //====================
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      MEM_WB_data   <= 0;
      MEM_WB_rd     <= 0;
      MEM_WB_opcode <= 0;
    end else begin
      MEM_WB_rd     <= EX_MEM_rd;
      MEM_WB_opcode <= EX_MEM_opcode;

      case (EX_MEM_opcode)
        7'b0000011: // lw
          MEM_WB_data <= data_mem[EX_MEM_alu_result];
        7'b0100011: // sw
          data_mem[EX_MEM_alu_result] <= EX_MEM_rs2_data;
        default:
          MEM_WB_data <= EX_MEM_alu_result;
      endcase
    end
  end

  //====================
  // Estágio WB
  //====================
  always @(posedge clock or posedge reset) begin
    if (reset) begin end
    else if (MEM_WB_opcode != 7'b0100011 && MEM_WB_rd != 0) begin
      regfile[MEM_WB_rd] <= MEM_WB_data;
    end
  end

endmodule
