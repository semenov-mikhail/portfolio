--Приложение №2 к Итоговой работе “SQL и получение данных”

--1) В каких городах больше одного аэропорта?

select city as "Город", count (city) as "Количество аэропортов"
from airports
group by city --Группируем по полю city
having count(city) >1 --выбираем значения где счетчик городов > 1

--2) В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета?

--explain analyze
--оставляем только уникальные значения в departure_airport. Не делаем доп манипуляций с полем arrival_airport т.к. если из него вылетает самолет, то он будет и в колонке departure_airport
select distinct f.departure_airport as "Аэропорты с самолетами макс. дальн"
from flights f 
 --джойним по коду самолета t.aircraft_code = f.aircraft_code. Используем внутреннее соединение -  в данном случае оно хорошо подходит.
join(
	--подзапросом сортируем таблицу по полю дальность перелета от большего к меньшему и оставляем только 1 максимальное значение. Это и есть наш самолет.
	select aircraft_code, model,  "range" 
	from aircrafts
	order by "range" desc
	limit 1) t on t.aircraft_code = f.aircraft_code 
	
--3) Вывести 10 рейсов с максимальным временем задержки вылета

select flight_no as "Рейс", 
	scheduled_departure "План врем отправления" , 
	actual_departure as "Фактич время отправления", 
	actual_departure - scheduled_departure as "Задержка вылета"
from flights
where actual_departure is not null
--сортируем, чтобы вывести максимальное время задержки вылета
order by actual_departure - scheduled_departure desc
--ограничиваем 10 строками выдачу
limit 10

--4) Были ли брони, по которым не были получены посадочные талоны?


--explain analyze 
select count(b.book_ref) as "Кол-во броней без пос.талона"
from bookings b 
--чтобы добраться до посадочных талонов подключаем таблицу с билетами по номеру бронирования. В одном бронировании может быть несколько билетов. Кол-во строк увеличивается.
join tickets t on t.book_ref = b.book_ref 
-- правильно выбираем джоин - в нашем случае левый, по номеру билета. Если не будет совпадения значений, к таким бронированиям будет добавлено NULL
left join boarding_passes bp on bp.ticket_no = t.ticket_no
--выбираем только NULL значения
where bp.boarding_no is null


--5) Найдите количество свободных мест для каждого рейса, их % отношение к общему количеству мест в самолете.
--Добавьте столбец с накопительным итогом - суммарное накопление количества вывезенных пассажиров из каждого аэропорта на каждый день. 
--Т.е. в этом столбце должна отражаться накопительная сумма - сколько человек уже вылетело из данного аэропорта на этом или более ранних рейсах в течении дня.

--explain analyze
--Считаем количество мест в каждой модели самолета
with ct1 as (
	select aircraft_code , count(seat_no) as ts
	from seats s 
	group by aircraft_code 
	),
--Находим сколько мест занято для каждого рейса на каждый перелет flight_id и формируем накопительный итог
ct2 as (	
	select t.flight_id, t.flight_no, t.aircraft_code, t.actual_departure::date, t.departure_airport , 
	--количество занятых мест на каждом рейсе
	t.count as os,
	--формируем накопительный итог по каждому аэропорту на каждый день
	sum(t.count) over (partition by t.departure_airport, t.actual_departure::date order by t.actual_departure) as sum_count
	from (
	--в подзапросе считаем количество человек на каждом рейсе
		select f.flight_id, f.flight_no, f.aircraft_code, f.actual_departure, f.departure_airport , count(bp.ticket_no) 
		from flights f
		join boarding_passes bp on bp.flight_id = f.flight_id
		where f.actual_departure is not null
		group by f.flight_id
		) t	
	)
select ct2.flight_no as "№ рейса",
ct1.ts - ct2.os as "Свободные места", --Вычитаем из общего кол-ва мест в самолете на рейсе  - количество занятых мест
--ct2.os as "Занято мест",
round((ct1.ts - ct2.os)/ct1.ts::numeric(5,2)*100.0,0) as "% свободн мест",
ct2.sum_count as "Накопление",
ct2.departure_airport as "Аэропорт",
ct2.actual_departure as "Дата рейса"
from ct2
join ct1 on ct1.aircraft_code = ct2.aircraft_code
	
--6) Найдите процентное соотношение перелетов по типам самолетов от общего количества.

--explain analyze
select 
	t.aircraft_code as "Тип самолета", 
	round(t.fl_by_aircraft/t.ttl_fl::numeric*100.0,0) as "% полетов от общего"
from (
	select
	--схлопываем по коду самолета
		distinct aircraft_code,
		--считаем количество перелетов по каждому типу самолета
		count(flight_id) over (partition by aircraft_code) fl_by_aircraft,
		--считаем общее количество перелетов
		count(flight_id) over () ttl_fl
	from flights
	group by flight_id , aircraft_code
) t
order by 2 desc

--7) Были ли города, в которые можно  добраться бизнес - классом дешевле, чем эконом-классом в рамках перелета?

--explain analyze
--Готовим в CTE необходимые данные, в частности, подтягиваем из связанных таблиц город назначения.
with ct1 as (
	select tf.flight_id, a.city, tf.fare_conditions, tf.amount 
	from ticket_flights tf 
	join flights f on f.flight_id = tf.flight_id 
	join airports a on a.airport_code = f.arrival_airport
	--по условию отбираем все строки в которых нет класса Комфорт
	where tf.fare_conditions != 'Comfort'
	--группируем, чтобы схлопнуть значения и получить уникальные стоимости для каждого перелета
	group by 1,2,3,4
)
select distinct ct1.city as "Город"
from ct1
--присоединяем ту же CTE по условию , чтобы провести сравнение
join ct1 ct_1 on ct_1.flight_id = ct1.flight_id and ct1.fare_conditions = 'Business' and ct_1.fare_conditions = 'Economy'
--здесь находим перелеты бизнес классом, которые по стоимость дешевле перелетов в тот же город Эконом-классом
where ct1.amount < ct_1.amount 


--8) Между какими городами нет прямых рейсов?

--создаем представление
--получаем список пар городов из таблицы airports
create view city_pairs as (
select da.city dac, aa.city aac
from airports da , airports aa 
)

--explain analyze
select distinct dac as "Город 1", aac as "Город 2"
from city_pairs
--убираем одинаковые пары
where dac!=aac
--теперь нужно отсечь те города, в которые осуществляются прямые перелеты
except select da1.city, aa1.city
	from flights f,
	    airports da1, airports aa1
	where f.departure_airport = da1.airport_code and 
		  f.arrival_airport = aa1.airport_code
order by 1,2

--9) Вычислите расстояние между аэропортами, связанными прямыми рейсами, сравните с допустимой максимальной дальностью перелетов в самолетах, обслуживающих эти рейсы

--к мат. представлению routes добавляю недостающие данные, дистинктом отсекаю дубли
select distinct 
	r.departure_airport as "А/п 1" , a.latitude as "Широта1", a.longitude as "Долгота1", 
	r.arrival_airport as "А/п 2", a2.latitude as "Широта2", a2.longitude as "Долгота2",
	a3.model as "Самолет на маршруте",a3."range" as "Дальность самолета",
	--Рассчитываю по формуле расстояние между а/п на основании того, что кратчайшее расстояние между двумя точками A и B на земной поверхности (если принять ее за сферу) 
	--определяется зависимостью: d = arccos {sin(latitude_a)·sin(latitude_b) + cos(latitude_a)·cos(latitude_b)·cos(longitude_a - longitude_b)}, где latitude_a и latitude_b — широты, 
	--longitude_a, longitude_b — долготы данных пунктов, d — расстояние между пунктами измеряется в радианах длиной дуги большого круга земного шара.
	--Расстояние между пунктами, измеряемое в километрах, определяется по формуле:
	--L = d·R, где R = 6371 км — средний радиус земного шара.
	acos(sind(a.latitude)*sind(a2.latitude) + cosd(a.latitude)*cosd(a2.latitude)*cosd(a.longitude - a2.longitude))*6371 as "Расст. между а/п",
	--Создаю case, чтобы выполнить проверку долетит ли самолет из Города1 в Город2 с учетом его дальности полета
	case 
		when a3.range >= acos(sind(a.latitude)*sind(a2.latitude) + cosd(a.latitude)*cosd(a2.latitude)*cosd(a.longitude - a2.longitude))*6371 then 'Долетит'
		else 'Не долетит'
	end as "Проверка" 
from routes r
join airports a on a.airport_code = r.departure_airport 
join airports a2 on a2.airport_code = r.arrival_airport 
join aircrafts a3 on a3.aircraft_code =r.aircraft_code 
order by 1, 2

--================================