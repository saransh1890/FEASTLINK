-- FEASTLINK | MySQL 8.0+ | Run: mysql -u root -p < database/schema.sql
CREATE DATABASE IF NOT EXISTS feastlink CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE feastlink;

CREATE TABLE IF NOT EXISTS users (
 user_id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100) NOT NULL,
 email VARCHAR(150) NOT NULL UNIQUE, phone VARCHAR(15) NOT NULL,
 password VARCHAR(255) NOT NULL,
 role ENUM('ORGANIZER','SHELTER_ADMIN','ADMIN') NOT NULL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_users_role(role)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS events (
 event_id INT AUTO_INCREMENT PRIMARY KEY, organizer_id INT NOT NULL,
 event_name VARCHAR(150) NOT NULL, event_type VARCHAR(100), event_date DATE NOT NULL,
 location VARCHAR(255) NOT NULL, expected_guests INT DEFAULT 0,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT fk_event_organizer FOREIGN KEY(organizer_id) REFERENCES users(user_id) ON DELETE CASCADE,
 INDEX idx_events_date(event_date), INDEX idx_events_organizer(organizer_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS shelter_homes (
 shelter_id INT AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL UNIQUE,
 shelter_name VARCHAR(150) NOT NULL, location VARCHAR(255) NOT NULL,
 contact_person VARCHAR(100) NOT NULL, phone VARCHAR(15) NOT NULL,
 number_of_residents INT NOT NULL, food_preference VARCHAR(100),
 availability_status ENUM('AVAILABLE','UNAVAILABLE') DEFAULT 'AVAILABLE',
 CONSTRAINT fk_shelter_user FOREIGN KEY(user_id) REFERENCES users(user_id) ON DELETE CASCADE,
 INDEX idx_shelter_availability(availability_status)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS surplus_food (
 food_id INT AUTO_INCREMENT PRIMARY KEY, event_id INT NOT NULL,
 food_name VARCHAR(150) NOT NULL, food_type ENUM('VEG','NON_VEG','OTHER') DEFAULT 'VEG',
 quantity VARCHAR(100) NOT NULL, estimated_meals INT NOT NULL,
 prepared_time DATETIME NOT NULL, available_until DATETIME NOT NULL,
 status ENUM('AVAILABLE','REQUESTED','ALLOCATED','EXPIRED','COMPLETED') DEFAULT 'AVAILABLE',
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT fk_food_event FOREIGN KEY(event_id) REFERENCES events(event_id) ON DELETE CASCADE,
 CONSTRAINT chk_food_meals CHECK(estimated_meals > 0),
 INDEX idx_food_status_expiry(status,available_until), INDEX idx_food_event(event_id), FULLTEXT INDEX ft_food_name(food_name)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS food_requests (
 request_id INT AUTO_INCREMENT PRIMARY KEY, food_id INT NOT NULL, shelter_id INT NOT NULL,
 requested_meals INT NOT NULL, request_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 status ENUM('PENDING','APPROVED','REJECTED','CANCELLED') DEFAULT 'PENDING',
 CONSTRAINT fk_request_food FOREIGN KEY(food_id) REFERENCES surplus_food(food_id) ON DELETE CASCADE,
 CONSTRAINT fk_request_shelter FOREIGN KEY(shelter_id) REFERENCES shelter_homes(shelter_id) ON DELETE CASCADE,
 CONSTRAINT chk_requested_meals CHECK(requested_meals > 0),
 INDEX idx_requests_status_date(status,request_date), INDEX idx_requests_shelter(shelter_id), INDEX idx_requests_food(food_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS food_allocations (
 allocation_id INT AUTO_INCREMENT PRIMARY KEY, request_id INT NOT NULL UNIQUE,
 allocated_meals INT NOT NULL, allocation_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 status ENUM('PENDING','CONFIRMED','COMPLETED','CANCELLED') DEFAULT 'PENDING',
 CONSTRAINT fk_allocation_request FOREIGN KEY(request_id) REFERENCES food_requests(request_id) ON DELETE CASCADE,
 CONSTRAINT chk_allocated_meals CHECK(allocated_meals > 0), INDEX idx_allocation_status(status)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS delivery (
 delivery_id INT AUTO_INCREMENT PRIMARY KEY, allocation_id INT NOT NULL UNIQUE,
 pickup_time DATETIME NULL, delivery_time DATETIME NULL,
 delivery_status ENUM('PENDING','PICKED_UP','IN_TRANSIT','DELIVERED','FAILED') DEFAULT 'PENDING',
 notes VARCHAR(500),
 CONSTRAINT fk_delivery_allocation FOREIGN KEY(allocation_id) REFERENCES food_allocations(allocation_id) ON DELETE CASCADE,
 INDEX idx_delivery_status(delivery_status)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS donation_history (
 donation_id INT AUTO_INCREMENT PRIMARY KEY, allocation_id INT NOT NULL UNIQUE,
 meals_served INT NOT NULL, completion_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 beneficiary_count INT, remarks VARCHAR(500),
 CONSTRAINT fk_history_allocation FOREIGN KEY(allocation_id) REFERENCES food_allocations(allocation_id) ON DELETE CASCADE,
 CONSTRAINT chk_meals_served CHECK(meals_served >= 0), INDEX idx_donation_date(completion_date)
) ENGINE=InnoDB;

-- Advanced concept 1: reusable SQL function
DROP FUNCTION IF EXISTS meals_remaining;
DELIMITER $$
CREATE FUNCTION meals_remaining(p_food_id INT) RETURNS INT READS SQL DATA
BEGIN
 DECLARE total_meals INT DEFAULT 0; DECLARE reserved_meals INT DEFAULT 0;
 SELECT estimated_meals INTO total_meals FROM surplus_food WHERE food_id=p_food_id;
 SELECT COALESCE(SUM(fr.requested_meals),0) INTO reserved_meals
 FROM food_requests fr WHERE fr.food_id=p_food_id AND fr.status IN ('PENDING','APPROVED');
 RETURN GREATEST(total_meals-reserved_meals,0);
END$$
DELIMITER ;

-- Advanced concept 2: trigger keeps food state synchronized with approved requests
DROP TRIGGER IF EXISTS trg_request_approved;
DELIMITER $$
CREATE TRIGGER trg_request_approved AFTER UPDATE ON food_requests FOR EACH ROW
BEGIN
 IF NEW.status='APPROVED' AND OLD.status<>'APPROVED' THEN
   UPDATE surplus_food SET status='ALLOCATED' WHERE food_id=NEW.food_id;
 END IF;
 IF NEW.status IN ('REJECTED','CANCELLED') AND OLD.status='PENDING' THEN
   UPDATE surplus_food SET status='AVAILABLE' WHERE food_id=NEW.food_id
     AND NOT EXISTS (SELECT 1 FROM food_requests r WHERE r.food_id=NEW.food_id AND r.status IN ('PENDING','APPROVED'));
 END IF;
END$$
DELIMITER ;

-- Advanced concept 3: procedure demonstrates stored procedure + transaction-safe allocation
DROP PROCEDURE IF EXISTS approve_food_request;
DELIMITER $$
CREATE PROCEDURE approve_food_request(IN p_request_id INT, IN p_allocated_meals INT)
BEGIN
 DECLARE v_food_id INT; DECLARE v_requested INT; DECLARE v_status VARCHAR(20);
 SELECT food_id,requested_meals,status INTO v_food_id,v_requested,v_status
 FROM food_requests WHERE request_id=p_request_id FOR UPDATE;
 IF v_status IS NULL OR v_status<>'PENDING' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Request is not pending'; END IF;
 IF p_allocated_meals<1 OR p_allocated_meals>v_requested THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid allocation quantity'; END IF;
 IF meals_remaining(v_food_id)<p_allocated_meals THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Insufficient available meals'; END IF;
 UPDATE food_requests SET status='APPROVED' WHERE request_id=p_request_id;
 INSERT INTO food_allocations(request_id,allocated_meals,status) VALUES(p_request_id,p_allocated_meals,'CONFIRMED');
 INSERT INTO delivery(allocation_id,delivery_status) VALUES(LAST_INSERT_ID(),'PENDING');
END$$
DELIMITER ;

-- Join-backed view for reporting/dashboard queries
CREATE OR REPLACE VIEW v_food_distribution AS
SELECT sf.food_id,sf.food_name,sf.food_type,sf.estimated_meals,sf.status AS food_status,
 e.event_name,e.location AS event_location,e.event_date,u.name AS organizer_name,
 COUNT(DISTINCT fr.request_id) AS request_count,COALESCE(SUM(fa.allocated_meals),0) AS meals_allocated
FROM surplus_food sf JOIN events e ON e.event_id=sf.event_id JOIN users u ON u.user_id=e.organizer_id
LEFT JOIN food_requests fr ON fr.food_id=sf.food_id
LEFT JOIN food_allocations fa ON fa.request_id=fr.request_id
GROUP BY sf.food_id,sf.food_name,sf.food_type,sf.estimated_meals,sf.status,e.event_name,e.location,e.event_date,u.name;

-- Helpful report queries (JOIN + aggregation)
-- SELECT * FROM v_food_distribution ORDER BY event_date DESC;
-- SELECT s.shelter_name, SUM(dh.meals_served) meals_served FROM shelter_homes s
-- JOIN food_requests r ON r.shelter_id=s.shelter_id JOIN food_allocations a ON a.request_id=r.request_id
-- JOIN donation_history dh ON dh.allocation_id=a.allocation_id GROUP BY s.shelter_id;
