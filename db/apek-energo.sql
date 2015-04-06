-- MySQL Workbench Synchronization
-- Generated: 2015-04-06 13:49
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
  `name` VARCHAR(45) NULL DEFAULT NULL,
  `lastname` VARCHAR(45) NULL DEFAULT NULL,
  `email` VARCHAR(45) NULL DEFAULT NULL,
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
  `name` VARCHAR(45) NOT NULL,
  PRIMARY KEY (`id`))
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

CREATE TABLE IF NOT EXISTS `apek-energo`.`companies` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `district_id` INT(11) NOT NULL,
  `name` VARCHAR(45) NOT NULL,
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
  `name` VARCHAR(45) NULL DEFAULT NULL,
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

CREATE TABLE IF NOT EXISTS `apek-energo`.`access_control` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `origin` VARCHAR(45) NULL DEFAULT NULL,
  PRIMARY KEY (`id`))
ENGINE = InnoDB
DEFAULT CHARACTER SET = utf8
COLLATE = utf8_general_ci;

INSERT INTO `apek-energo`.`roles` (`name`)
VALUES
	(`admin`),
	(`manager`),
	(`user`);


SET SQL_MODE=@OLD_SQL_MODE;
SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;
SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS;
