`timescale 1ns / 1ps

module tb_pipeline;

  reg clock;
  reg reset;

  // Instância do módulo principal
  RISCV_Pipeline uut (
    .clock(clock),
    .reset(reset)
  );

  // Clock: alterna a cada 5ns => período de 10ns
  always #5 clock = ~clock;

  // Inicialização e simulação
  initial begin
    $display("Iniciando simulação...");
    clock = 0;
    reset = 1;

    // Segura o reset por 2 ciclos
    #10 reset = 0;

    // Roda a simulação por tempo suficiente para executar todas as instruções (pelo menos 40 ciclos)
    #400;

    $display("\n=== Registradores ===");
    $display("x1 = %d", uut.regfile[1]);
    $display("x2 = %d", uut.regfile[2]);
    $display("x3 = %d", uut.regfile[3]);
    $display("x4 = %d", uut.regfile[4]);
    $display("x5 = %d", uut.regfile[5]);

    $display("\n=== Memória de dados ===");
    $display("mem[0] = %d", uut.data_mem[0]);

    $display("\n=== Fim da simulação ===");
    $finish;
  end

endmodule
