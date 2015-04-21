USE `apek-energo`;

DROP PROCEDURE IF EXISTS build_amortization;

DELIMITER $$
CREATE PROCEDURE build_amortization()
begin
    DECLARE done INT DEFAULT FALSE;
    DECLARE id, usage_limit, val, reconstruction, install_year, cost INT DEFAULT NULL;
    DECLARE y, ul INT DEFAULT NULL;
    DECLARE norma, ca, am, ya FLOAT DEFAULT NULL;

    DECLARE cur CURSOR FOR
        SELECT o.id, o.last_usage_limit, i.value, o.reconstruction_year, o.install_year, o.cost
        FROM objects o
        JOIN categories c ON c.id = o.object_name
        JOIN amortization_indexes i ON i.category_id = c.category_name;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN cur;

    TRUNCATE `amortization_calculations`;
    read_loop: LOOP
        SET norma = NULL;
        SET ca = NULL;
        SET ul = NULL;
        SET ya = NULL;
        SET am = NULL;

        FETCH cur INTO id, usage_limit, val, reconstruction, install_year, cost;
        IF done THEN
            LEAVE read_loop;
        END IF;

        SELECT YEAR(CURDATE()) INTO y;

        IF usage_limit IS NOT NULL AND usage_limit <> 0 THEN
            SET norma = 1 / usage_limit;
            SET ca = norma * cost;
        END IF;

        IF reconstruction IS NOT NULL THEN
            SET ul = val - y + reconstruction;
        ELSEIF install_year IS NOT NULL THEN
            SET ul = val - y + install_year;
        END IF;

        IF ul IS NOT NULL THEN
            SET ya = 1 / ul;
            SET am = cost * ya;
        END IF;

        INSERT INTO `amortization_calculations`(
            `object_id`,
            `norma`,
            `calculated_amortization`,
            `usage_norma`,
            `usage_limit`,
            `year_amortization`,
            `amortization`
        ) VALUES (id, norma, ca, val, ul, ya, am);
    END LOOP;

    CLOSE cur;
end;$$

DELIMITER ;
