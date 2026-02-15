show databases;
use  iip;
show tables;
SET SQL_SAFE_UPDATES = 0;
select * from `index of industrial production (1)`;
DELIMITER //

CREATE PROCEDURE UnpivotIIPData()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE col_name VARCHAR(64);
    DECLARE sql_query LONGTEXT DEFAULT '';
    
    -- Get all column names that look like dates (YYYY:MM)
    DECLARE cur CURSOR FOR 
        SELECT COLUMN_NAME 
        FROM INFORMATION_SCHEMA.COLUMNS 
        WHERE TABLE_NAME = 'index of industrial production (1)' 
        AND COLUMN_NAME REGEXP '^[0-9]{4}:[0-9]{2}';
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO col_name;
        IF done THEN
            LEAVE read_loop;
        END IF;

        -- Build the UNION ALL segments
        IF sql_query != '' THEN
            SET sql_query = CONCAT(sql_query, ' UNION ALL ');
        END IF;
        
        SET sql_query = CONCAT(sql_query, 
            'SELECT `Item Description`, "', col_name, '" AS `Date`, `', col_name, '` AS `Value` ',
            'FROM `index of industrial production (1)`');
    END LOOP;

    CLOSE cur;

    -- Create a new table with the results
    SET @final_query = CONCAT('CREATE TABLE unpivoted_iip AS ', sql_query);
    
    PREPARE stmt FROM @final_query;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //

DELIMITER ;

-- Run the procedure
CALL UnpivotIIPData();

-- View your results
SELECT * FROM unpivoted_iip;

USE iip;
SET SQL_SAFE_UPDATES = 0;

-- 1. Clean up old versions so the script never fails
DROP PROCEDURE IF EXISTS UnpivotIIPData;
DROP TABLE IF EXISTS unpivoted_iip;

DELIMITER //

CREATE PROCEDURE UnpivotIIPData()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE col_name VARCHAR(64);
    DECLARE sql_query LONGTEXT DEFAULT '';
    
    -- Cursor to find all the date columns
    DECLARE cur CURSOR FOR 
        SELECT COLUMN_NAME 
        FROM INFORMATION_SCHEMA.COLUMNS 
        WHERE TABLE_NAME = 'index of industrial production (1)' 
        AND COLUMN_NAME REGEXP '^[0-9]{4}:[0-9]{2}';
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO col_name;
        IF done THEN
            LEAVE read_loop;
        END IF;

        IF sql_query != '' THEN
            SET sql_query = CONCAT(sql_query, ' UNION ALL ');
        END IF;
        
        -- We extract the YYYY:MM and turn it into a standard YYYY-MM-01 date
        SET sql_query = CONCAT(sql_query, 
            'SELECT `Item Description`, ',
            'STR_TO_DATE(CONCAT(LEFT("', col_name, '", 7), ":01"), "%Y:%m:%d") AS `MonthDate`, ',
            '`', col_name, '` AS `Value` ',
            'FROM `index of industrial production (1)`');
    END LOOP;

    CLOSE cur;

    -- Create the table automatically
    SET @final_query = CONCAT('CREATE TABLE unpivoted_iip AS ', sql_query);
    
    PREPARE stmt FROM @final_query;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //

DELIMITER ;

-- 2. Run the logic
CALL UnpivotIIPData();

-- 3. Check your final cleaned data
SELECT * FROM unpivoted_iip ORDER BY MonthDate DESC;

SELECT * FROM unpivoted_iip ORDER BY MonthDate DESC limit 20;

CREATE VIEW sector_data AS 
SELECT * FROM unpivoted_iip 
WHERE `Item Description` != 'General Index';

CREATE TABLE iip_final_analytics AS
SELECT 
    `Item Description`, 
    MonthDate, 
    `Value`,
    -- Calculate Year-on-Year Growth
    ROUND(((`Value` - LAG(`Value`, 12) OVER (PARTITION BY `Item Description` ORDER BY MonthDate)) 
    / LAG(`Value`, 12) OVER (PARTITION BY `Item Description` ORDER BY MonthDate)) * 100, 2) AS YoY_Growth,
    -- Calculate Month-on-Month Growth
    ROUND(((`Value` - LAG(`Value`, 1) OVER (PARTITION BY `Item Description` ORDER BY MonthDate)) 
    / LAG(`Value`, 1) OVER (PARTITION BY `Item Description` ORDER BY MonthDate)) * 100, 2) AS MoM_Growth
FROM unpivoted_iip;

select * from iip_final_analytics ;


DROP TABLE IF EXISTS iip_structural_analysis;
CREATE TABLE iip_structural_analysis AS
WITH IndustryBounds AS (
    -- Get the first and last recorded values for each industry
    SELECT 
        `Item Description`,
        MIN(CASE WHEN MonthDate = '2012-04-01' THEN `Value` END) as Start_Value,
        MAX(CASE WHEN MonthDate = '2025-12-01' THEN `Value` END) as End_Value
    FROM iip_final_resume_ready
    GROUP BY `Item Description`
)
SELECT 
    `Item Description`,
    Start_Value,
    End_Value,
    -- Total Growth Percentage
    ROUND(((End_Value - Start_Value) / Start_Value) * 100, 2) AS Total_Growth_Pct,
    -- CAGR Calculation (13.7 years)
    ROUND((POW((End_Value / Start_Value), (1 / 13.7)) - 1) * 100, 2) AS CAGR_Pct,
    -- Average YoY for the whole period
    (SELECT ROUND(AVG(YoY_Growth), 2) 
     FROM iip_final_resume_ready b 
     WHERE b.`Item Description` = IndustryBounds.`Item Description`) AS Avg_YoY
FROM IndustryBounds
WHERE Start_Value IS NOT NULL AND End_Value IS NOT NULL;

SELECT DISTINCT `Item Description` FROM iip_final_resume_ready;










