/* 
BSD 3-Clause License

Copyright (c) 2020, ilyajob05
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/



module spi_clock_gen #(parameter  Nc=6,              //Разрядность количества импульсов, которые надо сгенерировать
                                  THalfSpiClk=10,    //Полупериод SPI Clock в тактах clk
                                  TCS=20             //Время между приходом строба start и первым импульсом spi_clk

)(
    input rst,                        //Асинхронный сброс
    input clk,                        //Тактовый генератор
    input start,                      //Старт генерации clk_count импульсов
    input [Nc-1:0]clk_count,          //Количество циклов, передачи данных
    output neg_edge_st,               //Строб отрицательного фронта
    output pos_edge_st,               //Строб положительного фронта
    output reg spi_clk,               //Текущее состояние на выходе тактового генератора
    output reg [Nc-1:0]clk_num,       //Номер текущего генерируемого импульса
    output reg [Nc-1:0]last_clk_num,  //Номер последнего импульса (включая тот, что передается при CS=1)
    output reg busy                   //Индикатор того, что модуль занят
);

function integer log2;            //Функция выисления логорифма по основанию 2
  input integer value;
  begin
    for (log2=0; value>0; log2=log2+1)
      value = value>>1;
  end
endfunction    

parameter Nt=(TCS>THalfSpiClk) ? log2(TCS) : log2(THalfSpiClk);    //Количество бит, необходимое для хранения текущего состояния таймера

reg [Nt-1:0]t_cnt;        //Таймер обратного отсчета времени цикла

always @(posedge clk, posedge rst)
    if(rst)
    begin
        t_cnt <= 0;
        spi_clk <= 0;
    end else 
        if(!busy)
        begin
            if(start)            //Если пришел строб старта
                t_cnt <= TCS;    //то ждем TCS и далее начинаем формировать импульсы
            spi_clk <= 0;        //В режиме ожидания держим spi_clk в 0
        end else
            begin
                if(t_cnt == 0)              //Если ожидание в полпериода закончилось
                begin
                    spi_clk <= ~spi_clk;    //Меняем состояние spi_clk
                    t_cnt <= THalfSpiClk;   //Ждем очередные пол периода
                end else
                        t_cnt <= t_cnt - 1; //В моменты ожидания обновляем значения таймера
            end        


always @(posedge clk, posedge rst)
    if(rst)
    begin
        busy <= 0;
        clk_num <= 0;
        last_clk_num <= 0;
    end    
    else if(!busy)       //Если модуль свободен
         begin
            if(start)    //И приходит строб на старт
            begin
                clk_num <=0;                    //то выставляем busy, вычисляем номер последнего цикла
                last_clk_num <= clk_count;      //и обнуляем счетчик импульсов
                busy <= 1;
            end
         end else
             if(neg_edge_st)                    //Если на выход был выдан отрицательный строб
             begin
                if(clk_num == last_clk_num)     //Если только что передали последний цикл
                begin
                    busy <= 0;                  //Снимаем busy и переходим к ожиданию нового строба start
                    clk_num <= 0;
                end else
                    begin
                        clk_num <= clk_num + 1; //Иначе увеличиваем номер формируемого импульса
                    end
                
             end

reg prev_spi_clk;        //Предыдущее значение spi_clk для определения фронтов

always @(posedge clk, posedge rst)
    if(rst)
        prev_spi_clk <= 0;
    else
        prev_spi_clk <= spi_clk;

//Формирование стробов фронтов
assign pos_edge_st = (!prev_spi_clk)&spi_clk;
assign neg_edge_st = prev_spi_clk&(!spi_clk);
        
endmodule


                              

