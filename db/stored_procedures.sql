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

    START TRANSACTION;
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

    COMMIT;
    CLOSE cur;
end;$$

DROP PROCEDURE IF EXISTS build_diagnostic; $$

CREATE PROCEDURE build_diagnostic()
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE id, name, subtype, s INT DEFAULT NULL;

    DECLARE cur CURSOR FOR
        SELECT o.id, c.category_name, o.objects_subtype, o.size
        FROM objects o
        JOIN categories c ON c.id = o.object_name;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    START TRANSACTION;

    TRUNCATE `diagnostic_calculations`;

    OPEN cur;
    read_loop: LOOP
        SET done = 0;
        SET @a = NULL;
        SET @b = NULL;

        FETCH cur INTO id, name, subtype, s;

        IF done THEN
            LEAVE read_loop;
        END IF;

        SELECT diametr
        FROM diagnostic_indexes
        WHERE category_id = name AND (object_subtype IS NULL OR object_subtype = subtype) AND diametr <= s
        ORDER BY diametr DESC LIMIT 1 INTO @a;

        SELECT diametr
        FROM diagnostic_indexes
        WHERE category_id = name AND (object_subtype IS NULL OR object_subtype = subtype) AND diametr > s
        ORDER BY diametr ASC LIMIT 1 INTO @b;

        IF s IS NULL THEN
            SET @c = s;
        ELSEIF @a IS NULL OR s = @b THEN
            SET @c = @b;
        ELSEIF @b IS NULL OR s = @a THEN
            SET @c = @a;
        ELSE
            SELECT (SIGN(s - ((@b + @a) / 2)) * (@b - @a) + @a + @b) / 2 INTO @c;
        END IF;

        INSERT INTO diagnostic_calculations(object_id, diametr) VALUES (id, @c);
    END LOOP;

    COMMIT;
    CLOSE cur;
END;$$

DELIMITER ;
