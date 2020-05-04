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


module test_spi_master (
    input nrst,                    //Асинхронный сброс
    input clk,                    //Тактовый генератор
    //input start,                  //Старт цикла передачи
	//output [(1<<3)-1:0]data_out,
	//output cyc_num,
	//output data_rdy,
	//output busy,
	output spi_cs,		// выбор кристалла
	output spi_clk,
	output spi_mosi,
	input spi_miso,
	output RsTx			// передатчик UART
);

wire rst;
assign rst = ~nrst;

wire [7:0]data_out;
wire [1:0]cyc_num;
wire data_rdy;
wire busy;

wire tickTimer;
// таймер
timer #(.period(5_000_000)) timertickTimer(.clk(clk), .rst(rst), .out(tickTimer));

reg [7:0]dataToSPI; //данные для отправки
spi_master #(.Nd(3),              //Размерность шины данных 2^Nd
             .Nc(3),              //Разрядность количества циклов приемо/передачи за одно соединение
             .THalfSpiClk(50),     //Полупериод SPI Clock в тактах clk
             .TCS(100)             //Время между сменой уровня CS и первым импульсом spi_clk    
)spi_tx(
    .rst(rst),                    //Асинхронный сброс
    .clk(clk),                    //Тактовый генератор
    .start(tickTimer),                  //Старт цикла передачи
    .cyc_count(3),      		//Количество циклов, передачи данных
    .data_in(dataToSPI),   //Даные, которые надо послать в ближайший возможный момент
    .data_out(data_out), //Принятые данные
    .cyc_num(cyc_num),   //Текущий номер цикла приемо/передачи за одно соединение
    .data_rdy(data_rdy),              //Данные в data_out обновлены, а данные из data_in должны быть обновлены на следующем такте после получения data_rdy
    .busy(busy),                  //Индикатор активного цикла приема/передачи данных
//Интерфейс SPI
    .spi_cs(spi_cs),                //Сhip Select
    .spi_clk(spi_clk),               //Clock
    .spi_mosi(spi_mosi),          //MOSI (Master output, Slave input)
    .spi_miso(spi_miso)                //MISO (Master input, Slave output)
);

// сигнал начала передачи данных по UART
reg uartStartSend;

// автомат формаирования последовательноси байт для передачи по SPI
always @(posedge clk, posedge rst)
if(rst)
	begin
	dataToSPI <= 8'h0B; //значение 0-го байта
	end
else
begin
	// если принят 3-й байт - передать его по UART
	if(data_rdy & (cyc_num == 2))
		uartStartSend <= 1; // старт передачи
	else
		uartStartSend <= 0;
	
	if(data_rdy)
	begin
		if(cyc_num == 0) // значение 1-го байта
			dataToSPI <= 8'h07;
		else if(cyc_num == 1) // значение 2-го байта
			dataToSPI <= 8'h0E;
		else
			dataToSPI <= 8'h0B; // значение 0-го и последующих байт
	end
end

// передатчик UART
uart_tx #(.T(921600)) uarttx(
.clk(clk), 
.rst(rst), 
.data(data_out), 
.start(uartStartSend), 
.dataOut(RsTx)/*, .ready(wTxReadyOut)*/);

endmodule
