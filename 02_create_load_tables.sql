PRAGMA foreign_keys = ON;

-- =========================================================
-- LIMPEZA
-- =========================================================

DROP TABLE IF EXISTS bridge_participation;
DROP TABLE IF EXISTS fact_ceremony_snapshot;
DROP TABLE IF EXISTS fact_nomination;

DROP TABLE IF EXISTS dim_nominee;
DROP TABLE IF EXISTS dim_film;
DROP TABLE IF EXISTS dim_class;
DROP TABLE IF EXISTS dim_category;
DROP TABLE IF EXISTS dim_ceremony;

DROP TABLE IF EXISTS participation;
DROP TABLE IF EXISTS nomination;
DROP TABLE IF EXISTS nominee;
DROP TABLE IF EXISTS film;
DROP TABLE IF EXISTS category;
DROP TABLE IF EXISTS ceremony;

-- staging table já existr por import
-- Exemplo esperado:
-- stg_oscars(
--   Ceremony, Year, Class, CanonicalCategory, Category, NomId,
--   Film, FilmId, Name, Nominees, NomineeIds, Winner,
--   Detail, Note, Citation, MultifilmNomination
-- );

-- =========================================================
-- MODELO OPERACIONAL
-- =========================================================

CREATE TABLE ceremony (
    ceremony_id      INTEGER PRIMARY KEY,
    ceremony_number  INTEGER NOT NULL,
    year             TEXT NOT NULL
);

CREATE TABLE film (
    film_id          TEXT PRIMARY KEY,
    title            TEXT
);

CREATE TABLE category (
    category_id          INTEGER PRIMARY KEY AUTOINCREMENT,
    class                TEXT NOT NULL,
    canonical_category   TEXT NOT NULL,
    category_name        TEXT NOT NULL,
    UNIQUE(class, canonical_category, category_name)
);

CREATE TABLE nominee (
    nominee_id       TEXT PRIMARY KEY,
    name             TEXT NOT NULL
);

CREATE TABLE nomination (
    nom_id                   TEXT PRIMARY KEY,
    ceremony_id              INTEGER NOT NULL,
    category_id              INTEGER NOT NULL,
    film_id                  TEXT,
    winner                   INTEGER NOT NULL DEFAULT 0,
    detail                   TEXT,
    note                     TEXT,
    citation                 TEXT,
    multifilm_nomination     INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (ceremony_id) REFERENCES ceremony(ceremony_id),
    FOREIGN KEY (category_id) REFERENCES category(category_id),
    FOREIGN KEY (film_id) REFERENCES film(film_id)
);

CREATE TABLE participation (
    nom_id           TEXT NOT NULL,
    nominee_id       TEXT NOT NULL,
    PRIMARY KEY (nom_id, nominee_id),
    FOREIGN KEY (nom_id) REFERENCES nomination(nom_id),
    FOREIGN KEY (nominee_id) REFERENCES nominee(nominee_id)
);

-- =========================================================
-- CARREGAR MODELO OPERACIONAL
-- =========================================================

INSERT INTO ceremony (ceremony_id, ceremony_number, year)
SELECT DISTINCT
    CAST(Ceremony AS INTEGER) AS ceremony_id,
    CAST(Ceremony AS INTEGER) AS ceremony_number,
    CAST(Year AS TEXT) AS year
FROM stg_oscars
WHERE Ceremony IS NOT NULL;

INSERT or IGNORE INTO film (film_id, title)
SELECT DISTINCT
    TRIM(FilmId) AS film_id,
    NULLIF(TRIM(Film), '') AS title
FROM stg_oscars
WHERE FilmId IS NOT NULL
  AND TRIM(FilmId) <> '';

INSERT INTO category (class, canonical_category, category_name)
SELECT DISTINCT
    TRIM(Class) AS class,
    TRIM(CanonicalCategory) AS canonical_category,
    TRIM(Category) AS category_name
FROM stg_oscars
WHERE Class IS NOT NULL
  AND CanonicalCategory IS NOT NULL
  AND Category IS NOT NULL;

INSERT or IGNORE INTO nominee (nominee_id, name)
SELECT DISTINCT
    TRIM(NomineeIds) AS nominee_id,
    COALESCE(NULLIF(TRIM(Name), ''), TRIM(Nominees)) AS name
FROM stg_oscars
WHERE NomineeIds IS NOT NULL
  AND TRIM(NomineeIds) <> '';

INSERT or IGNORE INTO nomination (
    nom_id,
    ceremony_id,
    category_id,
    film_id,
    winner,
    detail,
    note,
    citation,
    multifilm_nomination
)
SELECT DISTINCT
    TRIM(s.NomId) AS nom_id,
    CAST(s.Ceremony AS INTEGER) AS ceremony_id,
    c.category_id,
    CASE
        WHEN s.FilmId IS NOT NULL AND TRIM(s.FilmId) <> '' THEN TRIM(s.FilmId)
        ELSE NULL
    END AS film_id,
    CASE
        WHEN s.Winner IN (1, '1', 1.0, '1.0', 'TRUE', 'true', 'True') THEN 1
        ELSE 0
    END AS winner,
    s.Detail,
    s.Note,
    s.Citation,
    CASE
        WHEN s.MultifilmNomination IN (1, '1', 1.0, '1.0', 'TRUE', 'true', 'True') THEN 1
        ELSE 0
    END AS multifilm_nomination
FROM stg_oscars s
JOIN category c
    ON TRIM(s.Class) = c.class
   AND TRIM(s.CanonicalCategory) = c.canonical_category
   AND TRIM(s.Category) = c.category_name
WHERE s.NomId IS NOT NULL
  AND TRIM(s.NomId) <> '';

INSERT INTO participation (nom_id, nominee_id)
SELECT DISTINCT
    TRIM(NomId) AS nom_id,
    TRIM(NomineeIds) AS nominee_id
FROM stg_oscars
WHERE NomId IS NOT NULL
  AND TRIM(NomId) <> ''
  AND NomineeIds IS NOT NULL
  AND TRIM(NomineeIds) <> '';

-- =========================================================
-- STAR SCHEMA
-- =========================================================

CREATE TABLE dim_ceremony (
    ceremony_key      INTEGER PRIMARY KEY,
    ceremony_number   INTEGER NOT NULL,
    year              TEXT NOT NULL,
    decade            INTEGER,
    century           INTEGER,
    era               TEXT
);

CREATE TABLE dim_category (
    category_key          INTEGER PRIMARY KEY,
    canonical_category    TEXT NOT NULL,
    category_name         TEXT NOT NULL
);

CREATE TABLE dim_class (
    class_key         INTEGER PRIMARY KEY,
    class_name        TEXT NOT NULL,
    class_group       TEXT NOT NULL
);

CREATE TABLE dim_film (
    film_key          INTEGER PRIMARY KEY,
    film_id           TEXT,
    title             TEXT
);

CREATE TABLE dim_nominee (
    nominee_key       INTEGER PRIMARY KEY,
    nominee_id        TEXT,
    name              TEXT
);

CREATE TABLE fact_nomination (
    nom_id                TEXT PRIMARY KEY,
    ceremony_key          INTEGER NOT NULL,
    category_key          INTEGER NOT NULL,
    class_key             INTEGER NOT NULL,
    film_key              INTEGER,
    nomination_count      INTEGER NOT NULL DEFAULT 1,
    win_count             INTEGER NOT NULL DEFAULT 0,
    detail                TEXT,
    note                  TEXT,
    citation              TEXT,
    multifilm             INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (ceremony_key) REFERENCES dim_ceremony(ceremony_key),
    FOREIGN KEY (category_key) REFERENCES dim_category(category_key),
    FOREIGN KEY (class_key) REFERENCES dim_class(class_key),
    FOREIGN KEY (film_key) REFERENCES dim_film(film_key)
);

CREATE TABLE bridge_participation (
    nom_id            TEXT NOT NULL,
    nominee_key       INTEGER NOT NULL,
    PRIMARY KEY (nom_id, nominee_key),
    FOREIGN KEY (nom_id) REFERENCES fact_nomination(nom_id),
    FOREIGN KEY (nominee_key) REFERENCES dim_nominee(nominee_key)
);

CREATE TABLE fact_ceremony_snapshot (
    snapshot_key                 INTEGER PRIMARY KEY AUTOINCREMENT,
    ceremony_key                 INTEGER NOT NULL,
    category_key                 INTEGER NOT NULL,
    class_key                    INTEGER NOT NULL,
    total_nominations            INTEGER NOT NULL,
    total_winners                INTEGER NOT NULL,
    total_films_nominated        INTEGER NOT NULL,
    total_distinct_nominees      INTEGER NOT NULL,
    avg_nominees_per_film        REAL,
    FOREIGN KEY (ceremony_key) REFERENCES dim_ceremony(ceremony_key),
    FOREIGN KEY (category_key) REFERENCES dim_category(category_key),
    FOREIGN KEY (class_key) REFERENCES dim_class(class_key),
    UNIQUE (ceremony_key, category_key, class_key)
);

-- =========================================================
--  DIMENSÕES
-- =========================================================

INSERT INTO dim_ceremony (
    ceremony_key,
    ceremony_number,
    year,
    decade,
    century,
    era
)
SELECT
    ceremony_id AS ceremony_key,
    ceremony_number,
    year,
    (CAST(SUBSTR(year, 1, 4) AS INTEGER) / 10) * 10 AS decade,
    ((CAST(SUBSTR(year, 1, 4) AS INTEGER) - 1) / 100) + 1 AS century,
    CASE
        WHEN CAST(SUBSTR(year, 1, 4) AS INTEGER) < 2000 THEN 'classic'
        ELSE 'modern'
    END AS era
FROM ceremony;

INSERT INTO dim_category (
    category_key,
    canonical_category,
    category_name
)
SELECT
    category_id AS category_key,
    canonical_category,
    category_name
FROM category;

INSERT INTO dim_class (
    class_key,
    class_name,
    class_group
)
SELECT DISTINCT
    DENSE_RANK() OVER (ORDER BY class) AS class_key,
    class AS class_name,
    CASE
        WHEN UPPER(class) IN ('ACTING', 'DIRECTING', 'WRITING', 'TITLE', 'SPECIAL')
            THEN 'Creative'
        WHEN UPPER(class) IN ('PRODUCTION', 'SCITECH')
            THEN 'Technical'
        ELSE 'Other'
    END AS class_group
FROM category;

INSERT INTO dim_film (
    film_key,
    film_id,
    title
)
SELECT
    ROW_NUMBER() OVER (ORDER BY film_id) AS film_key,
    film_id,
    title
FROM film;

INSERT INTO dim_nominee (
    nominee_key,
    nominee_id,
    name
)
SELECT
    ROW_NUMBER() OVER (ORDER BY nominee_id) AS nominee_key,
    nominee_id,
    name
FROM nominee;

-- =========================================================
-- FACT_NOMINATION
-- =========================================================

INSERT INTO fact_nomination (
    nom_id,
    ceremony_key,
    category_key,
    class_key,
    film_key,
    nomination_count,
    win_count,
    detail,
    note,
    citation,
    multifilm
)
SELECT
    n.nom_id,
    n.ceremony_id AS ceremony_key,
    n.category_id AS category_key,
    dc.class_key,
    df.film_key,
    1 AS nomination_count,
    CASE WHEN n.winner = 1 THEN 1 ELSE 0 END AS win_count,
    n.detail,
    n.note,
    n.citation,
    n.multifilm_nomination
FROM nomination n
JOIN category c
    ON n.category_id = c.category_id
JOIN dim_class dc
    ON c.class = dc.class_name
LEFT JOIN dim_film df
    ON n.film_id = df.film_id;

-- =========================================================
-- BRIDGE_PARTICIPATION
-- =========================================================

INSERT INTO bridge_participation (nom_id, nominee_key)
SELECT
    p.nom_id,
    dn.nominee_key
FROM participation p
JOIN dim_nominee dn
    ON p.nominee_id = dn.nominee_id;

-- =========================================================
-- FACT_CEREMONY_SNAPSHOT
-- =========================================================

INSERT INTO fact_ceremony_snapshot (
    ceremony_key,
    category_key,
    class_key,
    total_nominations,
    total_winners,
    total_films_nominated,
    total_distinct_nominees,
    avg_nominees_per_film
)
SELECT
    fn.ceremony_key,
    fn.category_key,
    fn.class_key,
    COUNT(*) AS total_nominations,
    SUM(fn.win_count) AS total_winners,
    COUNT(DISTINCT fn.film_key) AS total_films_nominated,
    COUNT(DISTINCT bp.nominee_key) AS total_distinct_nominees,
    CASE
        WHEN COUNT(DISTINCT fn.film_key) = 0 THEN NULL
        ELSE CAST(COUNT(DISTINCT bp.nominee_key) AS REAL) / COUNT(DISTINCT fn.film_key)
    END AS avg_nominees_per_film
FROM fact_nomination fn
LEFT JOIN bridge_participation bp
    ON fn.nom_id = bp.nom_id
GROUP BY
    fn.ceremony_key,
    fn.category_key,
    fn.class_key;

-- =========================================================
-- ÍNDICES ÚTEIS
-- =========================================================

CREATE INDEX idx_nomination_ceremony ON nomination(ceremony_id);
CREATE INDEX idx_nomination_category ON nomination(category_id);
CREATE INDEX idx_nomination_film ON nomination(film_id);

CREATE INDEX idx_participation_nominee ON participation(nominee_id);

CREATE INDEX idx_fact_nomination_ceremony ON fact_nomination(ceremony_key);
CREATE INDEX idx_fact_nomination_category ON fact_nomination(category_key);
CREATE INDEX idx_fact_nomination_class ON fact_nomination(class_key);
CREATE INDEX idx_fact_nomination_film ON fact_nomination(film_key);

CREATE INDEX idx_bridge_nominee ON bridge_participation(nominee_key);

