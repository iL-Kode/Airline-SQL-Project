DROP TABLE IF EXISTS CreditCard;
DROP TABLE IF EXISTS Ticket;
DROP TABLE IF EXISTS Contact;
DROP TABLE IF EXISTS Booking;
DROP TABLE IF EXISTS Reservation;
DROP TABLE IF EXISTS Reservation_Extra;
DROP TABLE IF EXISTS Passenger;
DROP TABLE IF EXISTS Flight;
DROP TABLE IF EXISTS WeeklySchedule;
DROP TABLE IF EXISTS Route;
DROP TABLE IF EXISTS Airport;
DROP TABLE IF EXISTS Weekday;
DROP TABLE IF EXISTS Year;

DROP PROCEDURE IF EXISTS addYear;
DROP PROCEDURE IF EXISTS addDay;
DROP PROCEDURE IF EXISTS addDestination;
DROP PROCEDURE IF EXISTS addRoute;
DROP PROCEDURE IF EXISTS addFlight;
DROP FUNCTION IF EXISTS calculateFreeSeats;
DROP FUNCTION IF EXISTS calculatePrice;
DROP TRIGGER IF EXISTS createTicket;
DROP PROCEDURE IF EXISTS addReservation;
DROP PROCEDURE IF EXISTS addPassenger;
DROP PROCEDURE IF EXISTS addContact;
DROP PROCEDURE IF EXISTS addPayment;





CREATE TABLE Year (
    year INTEGER PRIMARY KEY,
    profitFactor DOUBLE,
    bookedPassengers INTEGER
);


CREATE TABLE Airport (
    aNum VARCHAR(3) PRIMARY KEY,
    name VARCHAR(30),
    country VARCHAR(30)
);

CREATE TABLE Route (
    routeID INTEGER AUTO_INCREMENT,
    departure VARCHAR(3),
    arrival VARCHAR(3),
    year INTEGER,
    routePrice DECIMAL(10,3),
    PRIMARY KEY (routeID, year),
    FOREIGN KEY (year) REFERENCES Year(year),
    FOREIGN KEY (departure) REFERENCES Airport(aNum),
    FOREIGN KEY (arrival) REFERENCES Airport(aNum)
);

CREATE TABLE WeeklySchedule (
    ID INTEGER AUTO_INCREMENT PRIMARY KEY,
    routeID INTEGER,
    year INTEGER,
    departureTime TIME,
    dayOfTheWeek VARCHAR(10),
    FOREIGN KEY (routeID, year) REFERENCES Route(routeID, year),
    FOREIGN KEY (year) REFERENCES Year(year)
);

CREATE TABLE Flight (
    flightNum INTEGER AUTO_INCREMENT PRIMARY KEY,
    week INTEGER,
    weeklyFlight INTEGER,
    scheduleID INTEGER,
    FOREIGN KEY (scheduleID) REFERENCES WeeklySchedule(ID)
);


CREATE TABLE Passenger (
    passportNum INTEGER PRIMARY KEY,
    name VARCHAR(30)
);



CREATE TABLE Reservation_Extra (
    resNum BIGINT PRIMARY KEY,
    flightNum INTEGER,
    FOREIGN KEY (flightNum) REFERENCES Flight(flightNum)
);


CREATE TABLE Reservation (
    resNum BIGINT,
    passenger INTEGER,
    PRIMARY KEY (resNum, passenger),
    FOREIGN KEY (resNum) REFERENCES Reservation_Extra(resNum),
    FOREIGN KEY (passenger) REFERENCES Passenger(passportNum)
);





CREATE TABLE Contact (
    phone BIGINT,
    email VARCHAR(30),
    reservation BIGINT,
    passenger INTEGER,
    PRIMARY KEY (reservation),
    FOREIGN KEY (reservation) REFERENCES Reservation_Extra(resNum),
    FOREIGN KEY (passenger) REFERENCES Passenger(passportNum)
);

CREATE TABLE Booking (
    ID INTEGER PRIMARY KEY,
    paid BOOLEAN,
    resNum BIGINT,
    year INTEGER,
    FOREIGN KEY (resNum) REFERENCES Reservation_Extra(resNum),
    FOREIGN KEY (year) REFERENCES `Year`(year)
    
);

CREATE TABLE Ticket (
    ticketNum INTEGER PRIMARY KEY,
    passenger INTEGER,
    bookingID INTEGER,
    FOREIGN KEY (bookingID) REFERENCES Booking(ID),
    FOREIGN KEY (passenger) REFERENCES Passenger(passportNum)
);

CREATE TABLE CreditCard (
    payerID BIGINT PRIMARY KEY,
    cardNum BIGINT,
    booking INTEGER,
    FOREIGN KEY (booking) REFERENCES Booking(ID)
);

CREATE TABLE Weekday (
    day VARCHAR(10),
    year INTEGER,
    weekdayFactor DOUBLE,
    PRIMARY KEY (day, year),
    FOREIGN KEY (year) REFERENCES Year(year)
);




DELIMITER //

/*addYear(year, factor)*/
CREATE PROCEDURE addYear(IN y INT, IN factor DOUBLE)
BEGIN
    INSERT INTO `Year` (year, profitFactor, bookedPassengers)
    VALUES (y, factor, 0);
END;

/*addDay(year, day, factor)*/
CREATE PROCEDURE addDay(IN y INT, IN day VARCHAR(10), IN factor DOUBLE)
BEGIN
    INSERT INTO Weekday (year, day, weekdayFactor)
    VALUES (y, day, factor);
END;

/*addDestination(airport_code, name, country)*/
CREATE PROCEDURE addDestination(IN airport_code VARCHAR(3), IN name VARCHAR(30), IN country VARCHAR(30))
BEGIN
    INSERT INTO Airport (aNum, name, country)
    VALUES (airport_code, name, country);
END;

/*addRoute(departure_code, arrival_code, year, route_price)*/
CREATE PROCEDURE addRoute(IN departure_code VARCHAR(3), IN arrival_code VARCHAR(3), IN year INT, IN route_price DOUBLE)
BEGIN
    INSERT INTO Route (departure, arrival, year, routePrice)
    VALUES (departure_code, arrival_code, year, route_price);

END;

/*addFlight(departure_airport_code, arrival_airport_code, year, day, departure_time)*/
CREATE PROCEDURE addFlight(
    IN dep_code VARCHAR(3),
    IN arr_code VARCHAR(3),
    IN y INT,
    IN d VARCHAR(10),
    IN departure_time TIME
)
BEGIN
    DECLARE rid INT;
    DECLARE schedule_id INT;
    DECLARE i INT DEFAULT 1;

    SELECT routeID INTO rid FROM Route
    WHERE departure = dep_code AND arrival = arr_code AND year = y
    LIMIT 1;

    IF rid IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Route does not exist for the given year';
    END IF;

    INSERT INTO WeeklySchedule (routeID, year, departureTime, dayOfTheWeek)
    VALUES (rid, y, departure_time, d);

    SET schedule_id = LAST_INSERT_ID();

    WHILE i <= 52 DO
        INSERT INTO Flight (week, weeklyFlight, scheduleID)
        VALUES (i, 1 , schedule_id);
        SET i = i + 1;
    END WHILE;
END;



CREATE FUNCTION calculateFreeSeats(flightnumber INT)
RETURNS INT
BEGIN
    DECLARE occupied_seats INT DEFAULT 0;

    SELECT COUNT(DISTINCT ticket.ticketNum)
    INTO occupied_seats
    FROM Ticket AS ticket
    JOIN Booking AS booking ON ticket.bookingID = booking.ID
    JOIN Reservation_Extra AS re ON booking.resNum = re.resNum
    WHERE  re.flightNum = flightnumber AND booking.paid = TRUE;
        
    RETURN 40 - occupied_seats;
END;

CREATE FUNCTION calculatePrice(flightnumber INT)
RETURNS DECIMAL(10,3) 
BEGIN
    DECLARE totalPrice DECIMAL(10,3) DEFAULT 0.0;
    DECLARE seats INT DEFAULT 0;
    DECLARE route_price DECIMAL(10,3);
    DECLARE weekday_factor DOUBLE;
    DECLARE profit_factor DOUBLE;

    SET seats = calculateFreeSeats(flightnumber);

    SELECT Route.routePrice, Weekday.weekdayFactor, Year.profitFactor
    INTO route_price, weekday_factor, profit_factor
    FROM Flight JOIN WeeklySchedule ON Flight.scheduleID = WeeklySchedule.ID
    JOIN Route ON WeeklySchedule.routeID = Route.routeID AND WeeklySchedule.year = Route.year
    JOIN Year ON Route.year = Year.year
	JOIN Weekday ON Weekday.year = Year.year AND Weekday.day = WeeklySchedule.dayOfTheWeek
    WHERE Flight.flightNum = flightnumber
	LIMIT 1;

    SET totalPrice = route_price * weekday_factor * (40 - seats + 1)/40 * profit_factor;

    RETURN totalPrice;

END;



CREATE TRIGGER createTicket
AFTER UPDATE ON Booking
FOR EACH ROW
BEGIN

    IF NEW.paid = TRUE AND (OLD.paid = FALSE OR OLD.paid IS NULL) THEN
        
        INSERT INTO Ticket (ticketNum, passenger, bookingID)
        SELECT 
            FLOOR(RAND() * 1000000000) + 1,
            r.passenger,
            NEW.ID
        FROM Reservation r
        WHERE r.resNum = NEW.resNum;
        
    END IF;
END;


CREATE PROCEDURE addReservation(
    IN departure_code VARCHAR(3),
    IN arrival_code VARCHAR(3),
    IN y INT,
    IN w INT,
    IN d VARCHAR(10),
    IN t TIME,
    IN num_passengers INT,
    OUT output_reservation_nr BIGINT
)
BEGIN
    DECLARE flight_num INT;
    DECLARE available_seats INT;
    DECLARE res_num BIGINT;

    SELECT Flight.flightNum INTO flight_num
    FROM Flight
    JOIN WeeklySchedule ON Flight.scheduleID = WeeklySchedule.ID
    JOIN Route ON WeeklySchedule.routeID = Route.routeID AND WeeklySchedule.year = Route.year
    WHERE Route.departure = departure_code 
        AND Route.arrival = arrival_code
        AND WeeklySchedule.year = y 
        AND WeeklySchedule.dayOfTheWeek = d 
        AND WeeklySchedule.departureTime = t
        AND Flight.week = w
    LIMIT 1;


    IF flight_num IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'There exist no flight for the given route, date and time';
    END IF;


    SET available_seats = calculateFreeSeats(flight_num);

    IF available_seats < num_passengers THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'There are not enough seats available on the chosen flight';
    END IF;

    SET res_num = FLOOR(RAND()*RAND()*13333337);
    SET output_reservation_nr = res_num;

    INSERT INTO Reservation_Extra (resNum, flightNum)
    VALUES (res_num, flight_num);

END;


CREATE PROCEDURE addPassenger(
    IN reservation_nr BIGINT,
    IN passport_number INT,
    IN passenger_name VARCHAR(30)
)
BEGIN
    DECLARE flight_num INT;

	IF EXISTS (
		SELECT 1 FROM Reservation
			WHERE resNum = reservation_nr AND passenger = passport_number
	) THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Passenger already added to this reservation';
	END IF;

    SELECT flightNum INTO flight_num
    FROM Reservation_Extra
    WHERE resNum = reservation_nr
    LIMIT 1;

    IF flight_num IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The given reservation number does not exist';
    END IF;

	IF EXISTS (
		SELECT 1
		FROM Booking
		WHERE resNum = reservation_nr AND paid = TRUE
	) THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The booking has already been paid and no further passengers can be added';
	END IF;

    INSERT IGNORE INTO Passenger (passportNum, name)
    VALUES (passport_number, passenger_name);

    INSERT INTO Reservation (resNum, passenger)
    VALUES (reservation_nr, passport_number);
END;


CREATE PROCEDURE addContact(
    IN reservation_nr BIGINT,
    IN passport_number INT,
    IN email VARCHAR(30),
    IN phone BIGINT
)
BEGIN

	IF NOT EXISTS (
        SELECT 1 FROM Reservation_Extra WHERE resNum = reservation_nr
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The given reservation number does not exist';
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM Reservation
        WHERE resNum = reservation_nr AND passenger = passport_number
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The person is not a passenger of the reservation';
    END IF;

    INSERT INTO Contact (reservation, passenger, email, phone)
    VALUES (reservation_nr, passport_number, email, phone);
END;


CREATE PROCEDURE addPayment(
    IN reservation_nr BIGINT,
    IN cardholder_name VARCHAR(30),
    IN credit_card_number BIGINT
)
BEGIN
    DECLARE passenger_count INT;
    DECLARE available_seats INT;
    DECLARE flight_num INT;
    DECLARE year_val INT;
    DECLARE booking_id INT;


    
    IF NOT EXISTS (
        SELECT 1 FROM Reservation_Extra WHERE resNum = reservation_nr
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The given reservation number does not exist';
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM Contact
        WHERE reservation = reservation_nr
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The reservation has no contact yet';
    END IF;
    
    SELECT flightNum INTO flight_num
    FROM Reservation_Extra
    WHERE resNum = reservation_nr
    LIMIT 1;

    IF flight_num IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Flight not found';
    END IF;

    SELECT WeeklySchedule.year INTO year_val
    FROM Flight
    JOIN WeeklySchedule ON Flight.scheduleID = WeeklySchedule.ID
    WHERE Flight.flightNum = flight_num;

    SELECT COUNT(*) INTO passenger_count
    FROM Reservation
    WHERE resNum = reservation_nr;

    SET available_seats = calculateFreeSeats(flight_num);
    IF available_seats < passenger_count THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'There are not enough seats available on the flight anymore, deleting reservation';
    END IF;

    SET booking_id = FLOOR(RAND()*RAND()*13333337);


    INSERT INTO Booking (ID, paid, resNum, year)
    VALUES (booking_id, FALSE, reservation_nr, year_val);

    INSERT INTO CreditCard (payerID, cardNum, booking)
    VALUES (FLOOR(RAND()*RAND()*13333337), credit_card_number, booking_id);
    
    UPDATE Booking SET paid = TRUE WHERE ID = booking_id;

END;


//
DELIMITER ;


CREATE OR REPLACE VIEW allFlights AS
SELECT
    dep_airport.name AS departure_city_name,
    arr_airport.name AS destination_city_name,
    ws.departureTime AS departure_time,
    ws.dayOfTheWeek AS departure_day,
    f.week AS departure_week,
    ws.year AS departure_year,
    calculateFreeSeats(f.flightNum) AS nr_of_free_seats,
    calculatePrice(f.flightNum) AS current_price_per_seat
FROM Flight f
JOIN WeeklySchedule ws ON f.scheduleID = ws.ID
JOIN Route r ON ws.routeID = r.routeID AND ws.year = r.year
JOIN Airport dep_airport ON r.departure = dep_airport.aNum
JOIN Airport arr_airport ON r.arrival = arr_airport.aNum;

SELECT * FROM allFlights;
