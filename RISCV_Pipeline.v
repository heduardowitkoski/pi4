module RISCV_Pipeline (
    input wire clock,
    input wire reset
);

  integer i;

  //===============================
  // Memórias e banco de registradores
  //===============================
  reg [31:0] instr_mem [0:21];    // Memoria de instruçoes
  reg [31:0] data_mem  [0:255];   // Memoria de dados
  reg [31:0] banco_regs [0:31];   // 32 registradores
  reg [31:0] register_address;    // Para armazenar endereço de retorno (x1)

  //======================
  // Registradores do Pipeline
  //======================

  // IF
  reg [31:0] IF_instr, IF_PC;

  // ID
  reg [31:0] ID_instr, ID_PC, ID_r1, ID_r2;
  reg [4:0]  ID_indiceR1, ID_indiceR2, ID_rd;
  reg [19:0] ID_imm, branch_valor;
  reg [6:0]  ID_opcode, ID_funct7;
  reg [2:0]  ID_funct3;
  reg [31:0] link;
  reg        ID_regwrite;

  // EX
  reg [31:0] EX_instr, EX_alu_result, EX_r2;
  reg [4:0]  EX_rd;
  reg [6:0]  EX_opcode;
  reg [19:0] EX_imm;
  reg [31:0] imm_sext, imm_shift, AUIPC_result;

  // MEM
  reg [31:0] MEM_instr, MEM_data;
  reg [4:0]  MEM_rd;
  reg [6:0]  MEM_opcode;
  reg        MEM_regwrite;

  //=======================
  // Contador de Programa
  //=======================
  reg [31:0] PC;

  //=======================
  // Sinais de Controle
  //=======================
  reg EX_salto_cond, flag_jump;
  reg EX_regwrite;

  //=======================
  // Sinais Intermediarios
  //=======================
  reg  [31:0] alu_result, branch_target;
  reg         branch_taken;
  reg         bge_taken, blt_taken;

  //=======================
  // Forwarding Logic
  //=======================
  wire fwdEX_r1 = EX_regwrite  && (EX_rd == ID_indiceR1) && (EX_rd != 0);
  wire fwdWB_r1 = MEM_regwrite && (MEM_rd == ID_indiceR1) && !fwdEX_r1 && (MEM_rd != 0);
  wire fwdEX_r2 = EX_regwrite  && (EX_rd == ID_indiceR2) && (EX_rd != 0);
  wire fwdWB_r2 = MEM_regwrite && (MEM_rd == ID_indiceR2) && !fwdEX_r2 && (MEM_rd != 0);

  //=======================
  // Seleção de operandos para ULA (ALU Mux)
  //=======================
  wire [31:0] alu_in1 = fwdEX_r1 ? EX_alu_result :
                        fwdWB_r1 ? MEM_data :
                        ID_r1;

  wire [31:0] alu_in2 = (ID_opcode == 7'b0010011 || ID_opcode == 7'b0000011 || ID_opcode == 7'b0100011) ?
                          ID_imm :
                        fwdEX_r2 ? EX_alu_result :
                        fwdWB_r2 ? MEM_data :
                        ID_r2;

  //=======================
  // Estagio EX: Execução
  //=======================
  always @(*) begin
    alu_result    = 0;
    branch_taken  = 0;
    branch_target = 0;

    case (ID_opcode)
      7'b0110011: begin // R-Type
        case (ID_funct7)
          7'b0000000: alu_result = alu_in1 + alu_in2;
          7'b0000001: alu_result = alu_in1 * alu_in2;
          7'b0100000: alu_result = alu_in1 - alu_in2;
          default:    alu_result = 0;
        endcase
      end

      7'b0010011,  // ADDI
      7'b0000011,  // LW
      7'b0100011:  // SW
        alu_result = alu_in1 + ID_imm;

      7'b0010111: // AUIPC
        alu_result = imm_shift + ID_PC;

      7'b1100011: begin // Branch
        bge_taken     = (ID_funct3 == 3'b101) && (alu_in1 >= alu_in2);
        blt_taken     = (ID_funct3 == 3'b100) && (alu_in1 <  alu_in2);
        branch_taken  = bge_taken || blt_taken;
        branch_target = ID_PC + ID_imm;
      end

      default: begin
        alu_result    = 0;
        branch_taken  = 0;
        branch_target = 0;
      end
    endcase
  end

  
    //=======================
  // Cache de Instruções (direta, 4 linhas)
  //=======================
  reg [31:0] instr_cache_data [0:3];  // Dados da cache
  reg [27:0] instr_cache_tag  [0:3];  // Tags da cache (endereÃ§os sem offset)
  reg        instr_cache_valid[0:3];  // Bits de validade da cache

  wire [1:0] cache_index = PC[3:2];   // Indexa 4 linhas (usando bits 3:2)
  wire [27:0] cache_tag   = PC[31:4]; // Tag (sem os 4 bits menos significativos)

    //=======================
  // Cache de Dados (direta, 4 linhas)
  //=======================
  reg [15:0] data_cache_data [0:3];  // Dados da cache (16 bits)
  reg [27:0] data_cache_tag  [0:3];  // Tags da cache
  reg        data_cache_valid[0:3];  // Bits de validade da cache

  wire [1:0]  data_cache_index = EX_alu_result[3:2];   // Indexa 4 linhas
  wire [27:0] data_cache_tag_addr = EX_alu_result[31:4]; // Tag

  
  
  //=======================
  // Inicialização
  //=======================
  initial begin
    PC = 0;

    // Exemplo de instruções: addi, add, sub, mul, etc.
    instr_mem[0] = 32'b00000000101000000000000010010011; // addi x1, x0, 10
    instr_mem[1] = 32'b00000001010000000000000100010011; // addi x2, x0, 20
    instr_mem[2] = 32'b00000000001000001000000110110011; // add x3, x1, x2
    instr_mem[3] = 32'b01000000010100011000001000110011; // sub x4, x3, x5
    instr_mem[4] = 32'b00000010001100100000001010110011; // mul x5, x4, x3
	instr_mem[5] = 32'b00000000000000000100001110000011; // lw x7, 0(x0)
	instr_mem[6] = 32'b00000000010000000110010000000011; // lw x8, 4(x0)


    // Zera banco de registradores e memoria
    for (i = 0; i < 32; i = i + 1) banco_regs[i] = 0;
    for (i = 0; i < 256; i = i + 1) data_mem[i]  = 0;
    
        for (i = 0; i < 4; i = i + 1) begin
      data_cache_valid[i] <= 0;
      data_cache_tag[i]   <= 0;
      data_cache_data[i]  <= 0;
    end

      // Inicializa a memória de dados
  data_mem[0] = 32'b00000000000000000000001000000000;
  data_mem[1] = 32'b00000000000000000000010000000000;
  data_mem[2] = 32'b00000000000000000000100000000000;
  data_mem[3] = 32'b00000000000000000001000000000000;
  end
    
 

  //=======================
  // Atualização do PC
  //=======================
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      PC               <= 0;
      register_address <= 0;
      link             <= 0;
    end else if (EX_salto_cond) begin
      PC <= branch_valor;
    end else if (flag_jump) begin
      PC   <= ID_PC + ID_imm;
      link <= PC + 4;
    end else begin
      PC <= PC + 4;
    end
  end

  //=======================
  // Estagio IF: Busca de instrução
  //=======================
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      IF_instr <= 0;
      IF_PC    <= 0;

      // Invalida a cache
      for (i = 0; i < 4; i = i + 1) begin
        instr_cache_valid[i] <= 0;
        instr_cache_tag[i]   <= 0;
        instr_cache_data[i]  <= 0;
      end

    end else if (EX_salto_cond || EX_opcode == 7'b1101111) begin
      IF_instr <= 0;
      IF_PC    <= 0;

    end else begin
      IF_PC <= PC;

      if (instr_cache_valid[cache_index] && instr_cache_tag[cache_index] == cache_tag) begin
        // Cache hit
        IF_instr <= instr_cache_data[cache_index];
      end else begin
        // Cache miss: busca da memoria principal
        IF_instr <= instr_mem[PC >> 2];
        instr_cache_data[cache_index]  <= instr_mem[PC >> 2];
        instr_cache_tag[cache_index]   <= cache_tag;
        instr_cache_valid[cache_index] <= 1;
      end
    end
  end


  //=======================
  // Estagio ID: Decodificação
  //=======================
  always @(posedge clock or posedge reset) begin
    if (reset || EX_salto_cond || EX_opcode == 7'b1101111) begin
      ID_instr     <= 0;
      ID_PC        <= 0;
      ID_r1        <= 0;
      ID_r2        <= 0;
      ID_indiceR1  <= 0;
      ID_indiceR2  <= 0;
      ID_imm       <= 0;
      ID_rd        <= 0;
      ID_opcode    <= 0;
      ID_funct3    <= 0;
      ID_funct7    <= 0;
      ID_regwrite  <= 0;
      imm_sext     <= 0;
      imm_shift    <= 0;
      flag_jump    <= 0;
    end else begin
      ID_instr  <= IF_instr;
      ID_PC     <= IF_PC;
      flag_jump <= 0;

      case (IF_instr[6:0])
        7'b0010011, // ADDI
        7'b0000011: begin // LW
          ID_opcode   <= IF_instr[6:0];
          ID_funct3   <= IF_instr[14:12];
          ID_rd       <= IF_instr[11:7];
          ID_indiceR1 <= IF_instr[19:15];
          ID_r1       <= banco_regs[IF_instr[19:15]];
          ID_imm      <= IF_instr[31:20];
          ID_regwrite <= 1;
        end

        7'b0100011: begin // SW
          ID_opcode   <= IF_instr[6:0];
          ID_funct3   <= IF_instr[14:12];
          ID_indiceR1 <= IF_instr[19:15];
          ID_indiceR2 <= IF_instr[24:20];
          ID_r1       <= banco_regs[IF_instr[19:15]];
          ID_r2       <= banco_regs[IF_instr[24:20]];
          ID_imm      <= {8'b0, IF_instr[31:25], IF_instr[11:7]};
          ID_regwrite <= 0;
        end

        7'b0110011: begin // R-Type
          ID_opcode   <= IF_instr[6:0];
          ID_funct3   <= IF_instr[14:12];
          ID_funct7   <= IF_instr[31:25];
          ID_rd       <= IF_instr[11:7];
          ID_indiceR1 <= IF_instr[19:15];
          ID_indiceR2 <= IF_instr[24:20];
          ID_r1       <= banco_regs[IF_instr[19:15]];
          ID_r2       <= banco_regs[IF_instr[24:20]];
          ID_regwrite <= 1;
        end

        7'b1100011: begin // bge e blt
          ID_imm        <= {8'b0, IF_instr[31:25], IF_instr[11:7]};
          ID_indiceR2   <= IF_instr[24:20];
          ID_indiceR1   <= IF_instr[19:15];
          ID_r2         <= banco_regs[IF_instr[24:20]];
          ID_r1         <= banco_regs[IF_instr[19:15]];
          ID_funct3     <= IF_instr[14:12];
          ID_opcode     <= IF_instr[6:0];
          ID_regwrite   <= 0;
        end

        7'b1101111: begin // jal
          ID_imm        <= {IF_instr[31], IF_instr[19:12], IF_instr[20], IF_instr[30:21], 1'b0};
          ID_rd         <= IF_instr[11:7];
          ID_opcode     <= IF_instr[6:0];
          ID_regwrite   <= 1;
          flag_jump     <= 1;
        end

        7'b0010111: begin // auipc
          imm_sext      <= {IF_instr[31:12], 12'b0};
          imm_shift     <= {IF_instr[31:12], 12'b0};
          ID_PC         <= IF_PC;
          ID_rd         <= IF_instr[11:7];
          ID_opcode     <= IF_instr[6:0];
          ID_regwrite   <= 1;
        end

        default: begin
          ID_opcode     <= 0;
          ID_regwrite   <= 0;
        end
      endcase
    end
  end

  //====================
  // Estagio EX
  //====================
   always @(posedge clock or posedge reset) begin
    if (reset) begin
      EX_instr    <= 0;
      EX_rd       <= 0;
      EX_opcode   <= 0;
      EX_regwrite <= 0;
      EX_alu_result <= 0;
      EX_r2       <= 0;
      EX_imm      <= 0;
      EX_salto_cond <= 0;
    end else begin
      EX_instr      <= ID_instr;
      EX_rd         <= ID_rd;
      EX_opcode     <= ID_opcode;
      EX_imm        <= ID_imm;
      EX_r2         <= ID_r2;
      EX_regwrite   <= ID_regwrite;
      EX_alu_result <= alu_result;

      if (ID_opcode == 7'b1100011) begin
        EX_salto_cond <= branch_taken;
        branch_valor  <= branch_target;
      end else begin
        EX_salto_cond <= 0;
      end
    end
  end


  //====================
  // Estagio MEM
  //====================
     always @(posedge clock or posedge reset) begin
    if (reset) begin
      MEM_instr   <= 0;
      MEM_data    <= 0;
      MEM_rd      <= 0;
      MEM_opcode  <= 0;
      MEM_regwrite <= 0;
    end else begin
      MEM_instr   <= EX_instr;
      MEM_rd      <= EX_rd;
      MEM_opcode  <= EX_opcode;
      MEM_regwrite <= EX_regwrite;

      if (EX_opcode == 7'b0000011) begin // LW
        // Leitura da cache de dados
        if (data_cache_valid[data_cache_index] && data_cache_tag[data_cache_index] == data_cache_tag_addr) begin
          // Cache hit
          MEM_data <= {16'b0, data_cache_data[data_cache_index]};
        end else begin
          // Cache miss: acessa memória principal e atualiza cache
          data_cache_data[data_cache_index]  <= data_mem[EX_alu_result >> 1]; // 16 bits por posição
          data_cache_tag[data_cache_index]   <= data_cache_tag_addr;
          data_cache_valid[data_cache_index] <= 1;
          MEM_data <= {16'b0, data_mem[EX_alu_result >> 1]};
        end
      end else if (EX_opcode == 7'b0100011) begin // SW
        // Escrita direta na memoria principal
        data_mem[EX_alu_result >> 1] <= EX_r2[15:0];

        // Invalida a linha da cache correspondente (write-through + no write-allocate)
        data_cache_valid[data_cache_index] <= 0;
      end else begin
        MEM_data <= EX_alu_result; // Para instruções tipo R e AUIPC
      end
    end
  end


  //====================
  // Estagio WB
  //====================
    always @(posedge clock or posedge reset) begin
    if (reset) begin
      // Nada a fazer no reset
    end else begin
      if (MEM_regwrite && MEM_rd != 0) begin
        banco_regs[MEM_rd] <= MEM_data;
        register_address   <= banco_regs[1]; // x1
      end
    end
  end


endmodule
