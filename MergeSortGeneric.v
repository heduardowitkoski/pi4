module MergeSortGeneric #(
    parameter N = 1024,
    parameter LOG2N = 10
)(
    input wire clock,
    input wire reset,
    output reg done
);

    reg [7:0] data_mem [0:N-1];
    reg [7:0] buffer   [0:N-1];

    integer left_ptr, right_ptr, out_ptr;
    integer start_idx;
    integer level;
    integer i;

    reg [7:0] left_val, right_val;
    reg left_valid, right_valid;

    localparam IDLE  = 3'd0,
               INIT  = 3'd1,
               READ  = 3'd2,
               MERGE = 3'd3,
               WRITE = 3'd4,
               DONE  = 3'd5;

    reg [2:0] state;

    integer idx;
    initial begin
       for (idx = 0; idx < N; idx = idx + 1)
            data_mem[idx] = $random % 256;
        done = 0;
        state = IDLE;
        level = 1;
        start_idx = 0;
        left_ptr = 0;
        right_ptr = 0;
        out_ptr = 0;
        i = 0;
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            done      <= 0;
            state     <= INIT;
            level     <= 1;
            start_idx <= 0;
            left_ptr  <= 0;
            right_ptr <= 0;
            out_ptr   <= 0;
            i         <= 0;
        end else begin
            case (state)
                INIT: begin
                    start_idx <= 0;
                    left_ptr  <= 0;
                    right_ptr <= (1 << (level - 1));
                    out_ptr   <= 0;
                    i         <= 0;
                    done      <= 0;
                    state     <= READ;
                end

                READ: begin
                    // Calcula validade dos ponteiros (atribuções NÃO bloqueantes para sincronizar leitura)
                    left_valid <= (left_ptr  < (1 << (level - 1))) && ((start_idx + left_ptr)  < N);
                    right_valid <= (right_ptr < (1 << level)) && ((start_idx + right_ptr) < N);

                    // Lê valores para comparação
                    if ((left_ptr  < (1 << (level - 1))) && ((start_idx + left_ptr)  < N))
                        left_val <= data_mem[start_idx + left_ptr];
                    else
                        left_val <= 8'hFF;

                    if ((right_ptr < (1 << level)) && ((start_idx + right_ptr) < N))
                        right_val <= data_mem[start_idx + right_ptr];
                    else
                        right_val <= 8'hFF;

                    state <= MERGE;
                end

                MERGE: begin
                    // Usa os valores lidos no ciclo anterior para merge e avanço
                    if (left_valid && right_valid) begin
                        if (left_val <= right_val) begin
                            buffer[out_ptr] <= left_val;
                            left_ptr <= left_ptr + 1;
                        end else begin
                            buffer[out_ptr] <= right_val;
                            right_ptr <= right_ptr + 1;
                        end
                        out_ptr <= out_ptr + 1;
                        state <= READ;
                    end else if (left_valid) begin
                        buffer[out_ptr] <= left_val;
                        left_ptr <= left_ptr + 1;
                        out_ptr <= out_ptr + 1;
                        state <= READ;
                    end else if (right_valid) begin
                        buffer[out_ptr] <= right_val;
                        right_ptr <= right_ptr + 1;
                        out_ptr <= out_ptr + 1;
                        state <= READ;
                    end else begin
                        i <= 0;
                        state <= WRITE;
                    end
                end

                WRITE: begin
                    if ((i < (1 << level)) && ((start_idx + i) < N)) begin
                        data_mem[start_idx + i] <= buffer[i];
                        i <= i + 1;
                    end else begin
                        start_idx <= start_idx + (1 << level);
                        if (start_idx + (1 << level) >= N) begin
                            if ((1 << level) >= N) begin
                                state <= DONE;
                                done <= 1;
                            end else begin
                                level <= level + 1;
                                start_idx <= 0;
                                state <= INIT;
                            end
                        end else begin
                            left_ptr <= 0;
                            right_ptr <= (1 << (level - 1));
                            out_ptr <= 0;
                            i <= 0;
                            state <= READ;
                        end
                    end
                end

                DONE: begin
                    done <= 1;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
