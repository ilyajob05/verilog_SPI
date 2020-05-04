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



module spi_master #(parameter Nd=3,              //Размерность шины данных 2^Nd
                              Nc=6,              //Разрядность количества циклов приемо/передачи за одно соединение
                              THalfSpiClk=10,    //Полупериод SPI Clock в тактах clk
                              TCS=20             //Время между сменой уровня CS и первым импульсом spi_clk    
)(
    input rst,                        //Асинхронный сброс
    input clk,                        //Тактовый генератор
    input start,                      //Старт цикла передачи
    input [Nc-1:0]cyc_count,          //Количество циклов, передачи данных
    input [(1<<Nd)-1:0]data_in,       //Даные, которые надо послать в ближайший возможный момент
    output reg [(1<<Nd)-1:0]data_out, //Принятые данные
    output reg [Nc-1:0]cyc_num,       //Текущий номер цикла приемо/передачи за одно соединение
    output reg data_rdy,                  //Данные в data_out обновлены, а данные из data_in должны быть обновлены на следующем такте после получения data_rdy
    output busy,                      //Индикатор активного цикла приема/передачи данных
//Интерфейс SPI
    output reg spi_cs,                //Сhip Select
    output spi_clk,               //Clock
    output reg spi_mosi,          //MOSI (Master output, Slave input)
    input spi_miso                //MISO (Master input, Slave output)
);

parameter N=(1<<Nd);        //Размерность блоков данных

//Тактовый генератор для SPI
wire pos_edge_st;   //Строб положительного фронта spi_clk
wire neg_edge_st;   //Строб отрицательного фронта spi_clk
wire clk_gen_busy;  //Флаг занятости генератора
wire [Nc+Nd-1:0]last_clk_num;  //Номер последнего импульса spi_clk (когда cs должен уже быть равен 1)
wire [Nc+Nd-1:0]clk_num;       //Номер текущего формируемого импульса

spi_clock_gen #(.Nc(Nc+Nd),                 //Разрядность количества импульсов, которые надо сгенерировать
                .THalfSpiClk(THalfSpiClk),  //Полупериод SPI Clock в тактах clk
                .TCS(TCS)                   //Время между приходом строба start и первым импульсом spi_clk
               ) spi_clock_gen (
    .rst(rst),                                      //Асинхронный сброс
    .clk(clk),                                      //Тактовый генератор
    .start(start),                                  //Старт генерации cyc_count импульсов
    .clk_count({cyc_count,{(Nd){1'b0}}}),           //Количество циклов, передачи данных
    .last_clk_num(last_clk_num),                    //Номер последнего импульса (включая тот, что передается при CS=1)
    .neg_edge_st(neg_edge_st),                      //Строб отрицательного фронта
    .pos_edge_st(pos_edge_st),                      //Строб положительного фронта
    .spi_clk(spi_clk),                              //Текущее состояние на выходе тактового генератора
    .clk_num(clk_num),                              //Номер текущего генерируемого импульса
    .busy(clk_gen_busy)                             //Индикатор того, что модуль занят
);

//Формирование сигнала busy
reg s_busy;     //Сигнал busy задержанным на 1 такт

always @(posedge clk, posedge rst)
    if(rst)
        s_busy <= 0;
    else
        s_busy <= clk_gen_busy;

assign busy = clk_gen_busy|s_busy;

//Формирование cyc_num
wire last_clk;  //флаг последнего импульса на выходе генератора
assign last_clk = (clk_num==last_clk_num);

always @(posedge clk, posedge rst)
    if(rst)
        cyc_num <= 0;
    else if(clk_gen_busy)
         begin
            if(!last_clk)
                cyc_num <= clk_num[Nc+Nd-1:Nd];        //Номер цикла - младшие биты номера импулься spi_clk
         end else
            cyc_num <= 0;

//Формирование сигнала CS
always @(posedge clk, posedge rst)
    if(rst)
        spi_cs <= 1;        //Нейтральное состояние линии CS = 1
    else 
        spi_cs <= ~(clk_gen_busy&(!last_clk)); //Если генератор spi_clk занят и не на последнем цикле, то CS=0
          
//Чтение данных
reg [N:0]temp_data_out;     //Сдвиговый регистр, используемый для хранения принимаемых данных в процессе цикла приемо/передачи

reg s_spi_miso;         //Данные от SPI Slave пропущенные через регистр

always @(posedge clk, posedge rst)
    if(rst)
        s_spi_miso <= 0;
    else
        s_spi_miso <= spi_miso;

always @(posedge clk, posedge rst)
    if(rst)
    begin
        temp_data_out <= 1;
        data_out <= 0;
        data_rdy <= 0;
    end    
    else begin
             if(!clk_gen_busy)      //В нейтральном состоянии генератора регистр данных держится в начальном значении
                temp_data_out <= 1;
             if(data_rdy)           //Снимаем data_rdy на следующем такте после установки
                data_rdy <= 0;

             if(pos_edge_st&(!last_clk))     //Чтение происходит по положительному фронту на всех импульсах кроме последнего
                temp_data_out <= {temp_data_out[N-1:0],s_spi_miso}; //Иначе вдвигаем очередной бит

             if(temp_data_out[N])            //Если единица доехала до старшего бита, значит закончился цикл приема данных
             begin
                 temp_data_out <= {{(N){1'b0}},1'b1};       
                 data_out <= temp_data_out[N-1:0];
                 data_rdy <= 1;
             end
         end

//Передача данных
reg s_data_rdy;     //Сигнал data_rdy задержанный на один такт

always @(posedge clk, posedge rst)
    if(rst)
      s_data_rdy <= 0;
    else
      s_data_rdy <= data_rdy;
  
reg [N-1:0]temp_data_in;     //Сдвиговый регистр, используемый для хранения принимаемых данных в процессе цикла приемо/передачи

always @(posedge clk, posedge rst)
    if(rst)
    begin
        temp_data_in <= 0;
        spi_mosi <= 0;    
    end    
    else begin
            if(!busy)
               spi_mosi <= 0;    
            if((!clk_gen_busy)&start)
            begin
                temp_data_in <= {data_in[N-2:0],1'b0};
                spi_mosi <= data_in[N-1];
            end           
            if(neg_edge_st)
            begin
                if(clk_num<(last_clk_num-1))
                    spi_mosi <= temp_data_in[N-1];      //Выводим в spi_mosi крайний левый бит и сдвигаем регистр
                else
                    spi_mosi <= 0;
                temp_data_in <= {temp_data_in[N-2:0],1'b0}; //Таким образом на последнем клоке spi_mosi сам перейдет в 0, так как по положительному фронту не будет сгенерировано data_rdy и в temp_data_in ничего не загрузится
            end
            if(s_data_rdy)          //На следующем такте после data_rdy обновляем регистр temp_data_in
               temp_data_in <= data_in; 
        end  

endmodule                                     
