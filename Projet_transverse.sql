-- Benjamin contentin Khalil Mazouz Lea Rivals Ashley Wendata Loeiticia Koanda

--1.a

ALTER TABLE client ADD Adherent_VIP varchar(50);

UPDATE client SET Adherent_VIP = CASE 
	WHEN vip =1 THEN 'VIP'
	when DATE_PART('year',datedebutadhesion) ='2016' then 'NEW_N2'
	when DATE_PART('year',datedebutadhesion) ='2017' then 'NEW_N1'
	when datefinadhesion >'2018/01/01' then 'ADHÉRENT' 
	when datefinadhesion <'2018/01/01' then 'CHURNER' 
END;

--1.b

create table CA_N1_N2 as
select idclient,
round(cast(sum(tic_totalttc) as numeric),2) as total, 
DATE_PART('year',tic_date) as année,mag_code
from entete_ticket
where DATE_PART('year',tic_date) in (2016,2017) 
and tic_totalttc >= 0
group by entete_ticket.idclient,DATE_PART('year',tic_date),mag_code;
ALTER TABLE CA_N1_N2
ALTER COLUMN année TYPE varchar(10); 

--1.c

ALTER TABLE client
add sexe varchar(50),
add age int,
add tranche_age varchar(50),
add sexe_X_age varchar(50);

update client set sexe = CASE 
		when civilite ilike 'madame' or civilite ilike 'mme' then 'Femme'
		when civilite ilike 'monsieur' or civilite ilike 'mr' then 'Homme'
		else 'NA'
	end;

update client set age =(DATE_PART('year',current_date) - DATE_PART('year', datenaissance));

update client set tranche_age = CASE 
		when datenaissance is null or age > 100 or age < 10 then 'NA'
		when age < 18 then '- 18 ans'
		when age between 18 and 25 then '18-25 ans'
		when age between 26 and 35 then '26-35 ans'
		when age between 36 and 45 then '36-45 ans'
		when age between 46 and 55 then '46-55 ans'
		when age between 56 and 65 then '56-65 ans'
		when age between 66 and 75 then '66-75 ans'
		else '+ 75 ans'
	END;

update client set sexe_X_age = CASE
		 when tranche_age like 'NA' or sexe like 'NA' then 'NA'
		 else concat(sexe,' ',tranche_age)
	END;
	
--2.a

create table client_actif_N2 as
select mag_code,count(idclient)as Nb_client_N2,sum(total) as Total_N2 from ca_n1_n2 where année='2016' and total > 0 group by mag_code;

create table client_actif_N1 as
select mag_code,count(idclient) as Nb_client_N1,sum(total) as Total_N1 from ca_n1_n2 where année='2017' and total > 0 group by mag_code;

create table tableau as 
select client.magasin, Nb_client_N2, Nb_client_N1, Total_N2, Total_N1
from client
left join  client_actif_N2 on client_actif_N2.mag_code = client.magasin
left join  client_actif_N1 on client_actif_N1.mag_code = client.magasin
Group by client.magasin,Nb_client_N2, Nb_client_N1, Total_N2, Total_N1;

ALTER TABLE tableau
add taux_client float4,
add diff_total float4,
add indice_ varchar(50);

update tableau set taux_client = round(((nb_client_N1- nb_client_N2)*1.0)/Nb_client_N2,4);
update tableau set diff_total = Total_N1 - Total_N2;
update tableau set indice_ = CASE 
	when taux_client > 0 and diff_total > 0 then 'positif'
	when taux_client < 0 and diff_total <  0 then 'négatif'
	else 'moyen'
end;

--2.b

-------------------
----CODE_INSEE-----
-------------------

drop table IF EXISTS insee;
create table insee 
(
	CODEINSEE varchar(10) primary key, 
	CODE_POSTAL varchar(50),
	COMMUNE varchar(50),
	DEPARTEMENT varchar(50),
	REGION varchar(50),
	STATUT varchar(50),
	ALTITUDE real,
	SUPERFICIE real,
	POPULATION real,
	GEOPOINT varchar(50),
	GEOSHAPE varchar(100000),
	IDGEOFLA varchar(10),
	CODE_COMMUNE varchar(10),
	CODE_CANTON varchar(10),
	CODE_ARDT varchar(10),
	CODE_DPT varchar(10),
	CODE_REGION varchar(10)
);

COPY insee FROM 'C:\Users\Public\INSEE.CSV' CSV HEADER delimiter ';' null '';

SELECT * from insee;

--------------------
--CREER_COORDONNEES-
--------------------

ALTER TABLE insee
ADD COLUMN longitude DECIMAL(12,9),
ADD COLUMN latitude DECIMAL(12,9);

UPDATE insee
SET longitude = CAST(SPLIT_PART(GEOPOINT, ',', 1) AS DECIMAL(12,9)),
    latitude = CAST(SPLIT_PART(GEOPOINT, ',', 2) AS DECIMAL(12,9));
	
-------------------
---LIAISON INSEE---
-------------------


CREATE TABLE liaisonclient AS
SELECT c.*, i.longitude, i.latitude
FROM client c
JOIN insee i
ON c.codeinsee = i.codeinsee;

ALTER TABLE liaisonclient
RENAME COLUMN longitude TO lon1;
ALTER TABLE liaisonclient
RENAME COLUMN latitude TO lat1;

SELECT * from liaisonclient;	
	
CREATE TABLE liaisonmag AS
SELECT m.*, i.longitude, i.latitude
FROM ref_magasin m
JOIN insee i
ON m.ville = i.commune;

ALTER TABLE liaisonmag
RENAME COLUMN longitude TO lon2;
ALTER TABLE liaisonmag
RENAME COLUMN latitude TO lat2;

SELECT * from liaisonmag;	

CREATE TABLE liaisonclientmag AS
SELECT m.*, c.*
FROM liaisonmag m
JOIN liaisonclient c
ON m.codesociete = c.magasin;

SELECT * from liaisonclientmag;

-------------------
--CALCUL DISTANCE--
-------------------

CREATE OR REPLACE FUNCTION haversine_distance(lat1 double precision, lon1 double precision, lat2 double precision, lon2 double precision) RETURNS double precision AS
$$
	SELECT 6371 * 2 * ASIN(SQRT(POWER(SIN(RADIANS((lat2 - lat1) / 2)), 2) + COS(RADIANS(lat1)) * COS(RADIANS(lat2)) * POWER(SIN(RADIANS((lon2 - lon1) / 2)), 2))) AS distance;

$$
LANGUAGE SQL IMMUTABLE;


ALTER TABLE liaisonclientmag
ADD COLUMN distance DOUBLE PRECISION;

UPDATE liaisonclientmag
SET distance = (SELECT haversine_distance(lat1, lon1, lat2, lon2));

ALTER TABLE liaisonclientmag
ADD COLUMN classedistance varchar(20);

UPDATE liaisonclientmag
SET classedistance =
  CASE 
    WHEN distance >= 0 AND distance < 5 THEN '0 - 5 km'
    WHEN distance >= 5 AND distance < 10 THEN '5 - 10 km'
    WHEN distance >= 10 AND distance < 20 THEN '10 - 20 km'
    WHEN distance >= 20 AND distance < 50 THEN '20 - 50 km'
    ELSE '50+ km'
  END;

SELECT * from liaisonclientmag;

--3.a
CREATE TABLE etude_par_univers as 
SELECT codeunivers, DATE_PART('year',tic_date) as annee, SUM(tic_totalttc) as CA_total
FROM entete_ticket
JOIN lignes_ticket ON entete_ticket.idticket = lignes_ticket.idticket
JOIN ref_article ON lignes_ticket.idarticle = ref_article.codearticle
GROUP BY codeunivers, annee
ORDER BY annee ASC;

--3.b
CREATE TABLE top_par_univers as 
SELECT codeunivers, codefamille, SUM(margesortie) as marge_totale
FROM ref_article
JOIN lignes_ticket ON ref_article.codearticle = lignes_ticket.idarticle
GROUP BY codeunivers, codefamille
ORDER BY marge_totale DESC
LIMIT 5;

