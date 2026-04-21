extends Resource
class_name GestureConstants

## Soglia di confidence per considerare una posa corretta (0.0 - 1.0)
const CONFIDENCE_THRESHOLD: float = 0.7

## Numero massimo di livelli nel gioco
const MAX_LEVEL: int = 10

## Scale possibili per il player (piccolo, medio, grande)
const SIZE_SCALES: Array[float] = [0.6, 1.0, 1.5]

## Distanza massima consentita tra controller e target (in metri)
const MAX_HAND_DISTANCE: float = 0.3

## Tempo di attesa prima di dire al player di riprovare (secondi)
const RETRY_WAIT_TIME: float = 2.0

## Tempo di attesa prima di andare al movimento successivo (secondi)
const SUCCESS_WAIT_TIME: float = 1.5
