module RISCV_Pipeline_MergeSort (
    input wire clock,
    input wire reset
);

    integer i;

    //=============================
    // Memória de Dados e Instruções
    //=============================
    reg [31:0] instr_mem [0:15];   
    reg [31:0] banco_regs[0:31];  

    reg [31:0] PC;

    //=============================
    // Pipeline Registers
    //=============================

    // IF/ID
    reg [31:0] IF_instr, IF_PC;

    // ID/EX
    reg [6:0]  ID_opcode;
    reg [4:0]  ID_rd;
    reg        ID_valid;

    // EX/MEM
    reg [4:0]  EX_rd;
    reg        EX_valid;
    reg        EX_start_sort;

    // MEM/WB
    reg [4:0]  MEM_rd;
    reg        MEM_valid;

    //=============================
    // MergeSort Acelerador
    //=============================
    wire mergesort_done;
    reg  start_sort;

    MergeSortGeneric mergesort_inst (
        .clock(clock),
        .reset(reset),
        .done(mergesort_done)
    );

    //=============================
    // PC Update
    //=============================
    always @(posedge clock or posedge reset) begin
        if (reset)
            PC <= 0;
        else if (!start_sort) // Só avança se não estiver rodando o mergesort
            PC <= PC + 4;
    end

    //=============================
    // IF Stage
    //=============================
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            IF_instr <= 0;
            IF_PC    <= 0;
        end else begin
            IF_instr <= instr_mem[PC >> 2];
            IF_PC    <= PC;
        end
    end

    //=============================
    // ID Stage
    //=============================
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            ID_opcode <= 0;
            ID_rd     <= 0;
            ID_valid  <= 0;
        end else begin
            ID_opcode <= IF_instr[6:0];
            ID_rd     <= IF_instr[11:7];
            ID_valid  <= 1;
        end
    end

    //=============================
    // EX Stage
    //=============================
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            EX_rd         <= 0;
            EX_valid      <= 0;
            start_sort    <= 0;
            EX_start_sort <= 0;
        end else begin
            EX_rd    <= ID_rd;
            EX_valid <= ID_valid;

            // Detecta a instrução de mergesort (opcode fictício)
            if (ID_opcode == 7'b1111111) begin
                start_sort    <= 1;
                EX_start_sort <= 1;
            end else begin
                EX_start_sort <= 0;
            end
        end
    end

    //=============================
    // MEM Stage
    //=============================
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            MEM_rd    <= 0;
            MEM_valid <= 0;
        end else begin
            MEM_rd    <= EX_rd;
            MEM_valid <= EX_valid;
        end
    end

    //=============================
    // WB Stage
    //=============================
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            // Nada
        end else begin
            if (MEM_valid && MEM_rd != 0) begin
                banco_regs[MEM_rd] <= 32'hDEAD_BEEF; // Sinaliza que terminou
            end
        end
    end

    //=============================
    // Controle do MergeSort
    //=============================
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            start_sort <= 0;
        end else begin
            if (EX_start_sort) begin
                start_sort <= 1;
            end else if (mergesort_done) begin
                start_sort <= 0; // Libera o pipeline quando termina
            end
        end
    end

    //=============================
    // Inicialização
    //=============================
    initial begin
        PC = 0;

        // Instrução fictícia que aciona o mergesort: opcode 1111111
        instr_mem[0] = 32'b00000000000000000000000001111111; // mergesort

        for (i = 0; i < 32; i = i + 1)
            banco_regs[i] = 0;
    end

endmodule
