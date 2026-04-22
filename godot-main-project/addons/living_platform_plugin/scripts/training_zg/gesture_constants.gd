extends Resource
class_name GestureConstants

## Soglia di confidence per considerare una posa corretta (0.0 - 1.0)
const CONFIDENCE_THRESHOLD: float = 0.5

## Tempo necessario di mantenimento della posa
const REQUIRED_HOLD: float = 2.0

## Numero massimo di livelli nel gioco
const MAX_LEVEL: int = 3

## Scale possibili per il player
const SIZE_SCALES: Array[float] = [0.1, 0.25, 0.5, 1.0, 1.5, 3.5]

## Tempo massimo di riconoscimento per ogni gesto (secondi), tempo di un livello
const RECOGNITION_DURATION: float = 30
