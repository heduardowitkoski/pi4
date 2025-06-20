`timescale 1ns/1ps

module tb_RISCV_MergeSort;

    reg clock;
    reg reset;

    integer i;  // ? Declaração movida para fora do bloco initial

    // Instancia o pipeline com o acelerador
    RISCV_Pipeline_MergeSort uut (
        .clock(clock),
        .reset(reset)
    );

    // Clock: 10ns período (100MHz)
    initial begin
        clock = 0;
        forever #5 clock = ~clock;
    end

    // Sequência de Reset
    initial begin
        reset = 1;
        #20;
        reset = 0;
    end

    // Monitoramento da simulação
    initial begin
        $display("===== Iniciando Simulacao =====");
        $monitor("Tempo = %0t | PC = %h | Done = %b | Start = %b", 
                 $time, uut.PC, uut.mergesort_inst.done, uut.start_sort);
    end

    // Condição de parada e impressão
    initial begin
        wait(uut.mergesort_inst.done == 1);
        #20;

        $display("\n===== Dados Ordenados na Memoria =====");
        for (i = 0; i < 32; i = i + 1) begin
            $display("data_mem[%0d] = %d", i, uut.mergesort_inst.data_mem[i]);
        end

        $display("===== Simulacao Finalizada =====");
        $stop;
    end

endmodule
