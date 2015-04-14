-- MySQL Workbench Synchronization
-- Generated: 2015-04-14 03:47
-- Model: New Model
-- Version: 1.0
-- Project: Name of the project
-- Author: Pavel Berezhnoy

SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0;
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;
SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='TRADITIONAL,ALLOW_INVALID_DATES';

CREATE SCHEMA IF NOT EXISTS `apek-energo` DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci ;

CREATE TABLE IF NOT EXISTS `apek-energo`.`users` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `role` INT(11) NOT NULL,
  `login` VARCHAR(45) NOT NULL,
  `pass` VARCHAR(45) NOT NULL,
  `name` VARCHAR(45)  DEFAULT NULL,
  `lastname` VARCHAR(45)  DEFAULT NULL,
  `email` VARCHAR(45)  DEFAULT NULL,
  PRIMARY KEY (`id`),
  INDEX `fk_users_roles_idx` (`role` ASC),
  UNIQUE INDEX `login_UNIQUE` (`login` ASC),
  CONSTRAINT `fk_users_roles`
    FOREIGN KEY (`role`)
    REFERENCES `apek-energo`.`roles` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`roles` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(45) NULL DEFAULT NULL,
  PRIMARY KEY (`id`))
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`districts` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(512) NOT NULL,
  PRIMARY KEY (`id`))
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`companies` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `district_id` INT(11) NOT NULL,
  `name` VARCHAR(512) NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `fk_companies_districts1_idx` (`district_id` ASC),
  CONSTRAINT `fk_companies_districts1`
    FOREIGN KEY (`district_id`)
    REFERENCES `apek-energo`.`districts` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`buildings` (
  `id` INT(11) NOT NULL,
  `company_id` INT(11) NOT NULL,
  `status` VARCHAR(64) NOT NULL DEFAULT '',
  `name` VARCHAR(512) NOT NULL DEFAULT '',
  `corpus` VARCHAR(512) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  INDEX `fk_buildings_companies1_idx` (`company_id` ASC),
  CONSTRAINT `fk_buildings_companies1`
    FOREIGN KEY (`company_id`)
    REFERENCES `apek-energo`.`companies` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`categories` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `object_name` VARCHAR(512) NOT NULL DEFAULT '',
  `category_name` VARCHAR(256)  DEFAULT NULL,
  PRIMARY KEY (`id`))
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`objects` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `size` INT(11) NULL DEFAULT 0,
  `isolation` INT(11) NOT NULL,
  `laying_method` INT(11) NOT NULL,
  `install_year` INT(11) NULL DEFAULT 2000,
  `reconstruction_year` INT(11) NULL DEFAULT 2000,
  `cost` INT(11) NULL DEFAULT 0,
  `object_name` INT(11) NOT NULL,
  `building` INT(11) NOT NULL,
  `characteristic` INT(11) NOT NULL,
  `characteristic_value` DOUBLE NULL DEFAULT 0.0,
  `wear` FLOAT(11) NULL DEFAULT 0.0,
  INDEX `fk_objects_isolations1_idx` (`isolation` ASC),
  INDEX `fk_objects_laying_methods1_idx` (`laying_method` ASC),
  INDEX `fk_objects_categories1_idx` (`object_name` ASC),
  INDEX `fk_objects_buildings1_idx` (`building` ASC),
  INDEX `fk_objects_characteristics1_idx` (`characteristic` ASC),
  PRIMARY KEY (`id`),
  CONSTRAINT `fk_objects_isolations1`
    FOREIGN KEY (`isolation`)
    REFERENCES `apek-energo`.`isolations` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_objects_laying_methods1`
    FOREIGN KEY (`laying_method`)
    REFERENCES `apek-energo`.`laying_methods` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_objects_categories1`
    FOREIGN KEY (`object_name`)
    REFERENCES `apek-energo`.`categories` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_objects_buildings1`
    FOREIGN KEY (`building`)
    REFERENCES `apek-energo`.`buildings` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_objects_characteristics1`
    FOREIGN KEY (`characteristic`)
    REFERENCES `apek-energo`.`characteristics` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`isolations` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(256) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`))
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`laying_methods` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(256) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`))
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`characteristics` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(512) NOT NULL DEFAULT '',
  `material` VARCHAR(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`))
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`buildings_meta` (
  `building_id` INT(11) NOT NULL,
  `characteristic` ENUM('ТВ','ТПЭ','ТП','ТВО','ЦТП') NOT NULL DEFAULT 'ТВ',
  `build_date` INT(2) NOT NULL DEFAULT 1800,
  `reconstruction_date` INT(2) NULL DEFAULT NULL,
  `heat_load` FLOAT(11) NULL DEFAULT NULL,
  `cost` DOUBLE NOT NULL DEFAULT 0.0,
  INDEX `fk_buildings_meta_buildings1_idx` (`building_id` ASC),
  CONSTRAINT `fk_buildings_meta_buildings1`
    FOREIGN KEY (`building_id`)
    REFERENCES `apek-energo`.`buildings` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;


DELIMITER $$

USE `apek-energo`$$
CREATE TRIGGER `apek-energo`.`characteristics_BEFORE_INSERT` BEFORE INSERT ON `characteristics`
FOR EACH ROW
begin
	case
		when new.`name` like '%латунь%' then set new.`material` = 'Латунь';
        when new.`name` like '%сталь%' then set new.`material` = 'Сталь';
        when new.`name` like '%чугун%' then set new.`material` = 'Чугун';
        when new.`name` like '%полипропилен%' then set new.`material` = 'Полипропилен';
        else
        begin
			set new.`material` = "";
		end;
	end case;
end
    $$


DELIMITER ;


SET SQL_MODE=@OLD_SQL_MODE;
SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;
SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS;
