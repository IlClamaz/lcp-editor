extends Resource
class_name GestureConstants

## Soglia di confidence per considerare una posa corretta (0.0 - 1.0)
const CONFIDENCE_THRESHOLD: float = 0.5

## Tolleranza massima dell'errore angolare (distanza su vettori normalizzati)
## usata per convertire errore -> confidenza. Valore storico: 0.5 (~30 gradi).
const POSE_MAX_TOLERANCE: float = 0.5

## Tempo necessario di mantenimento della posa
const REQUIRED_HOLD: float = 2.0

## Numero massimo di livelli nel gioco
const MAX_LEVEL: int = 3

## Scale possibili per il player
const SIZE_SCALES: Array[float] = [1.0, 2.0, 3.0, 4.0]

## Tempo della finestra di riconoscimento, in cui il character rimane bloccato
const HOLD_WINDOW: float = 20

# Tempo totale del gioco, dopo il quale si perde
const GAME_TIMER: float = 1


# Allo scadere dei 60 secondi, fallimento, 
# Lui diventa piu grande, e appare il messaggio "Fallito! Ecco un'altra possibilità"


