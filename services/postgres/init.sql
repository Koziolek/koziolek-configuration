-- Skrypt inicjalizacyjny dla trzech baz danych
-- Używa CREATE DATABASE IF NOT EXISTS (PostgreSQL 9.1+)

-- Tworzenie bazy danych 'ghost-track' (nazwa w cudzysłowach przez myślnik)
SELECT 'CREATE DATABASE "ghost-track"'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ghost-track')\gexec

-- Tworzenie bazy danych 'home'
SELECT 'CREATE DATABASE home'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'home')\gexec

-- Informacje o utworzonych bazach
    \echo 'Inicjalizacja baz danych zakończona.'
    \echo 'Dostępne bazy danych:'
    \l