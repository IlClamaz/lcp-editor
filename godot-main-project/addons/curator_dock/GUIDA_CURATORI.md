Di seguito trovi una guida **user-friendly** (non tecnica) pensata per i curatori. Puoi copiarla in un file tipo `GUIDA_CURATORI.md` o in un PDF.

---

# Guida Curatori — Curator Dock (Godot)

Questa guida spiega come usare il pannello **Curator Dock** dentro Godot per costruire il **layout** di una scena 3D a partire dagli oggetti presenti nel database Omeka S.

L’idea è semplice:

* **Il database (Omeka S)** contiene gli oggetti e le loro informazioni.
* **La scena (Godot)** contiene la disposizione spaziale (layout) di quegli oggetti.
* La **lista nel dock** è un “magazzino” di oggetti dal DB: non cambia quando sposti/aggiungi oggetti in scena. Si aggiorna **solo** quando premi “Aggiorna lista (DB)”.

---

## 1) Requisiti: che scena devo aprire?

Per funzionare, la scena deve avere come nodo radice un **LivingScene**.

* Se apri una scena che non è un LivingScene, vedrai un avviso nel dock e molti pulsanti saranno disabilitati.

---

## 2) Dove trovo il Curator Dock?

Nel pannello dell’editor (dock laterale) dovresti vedere **Curator Dock** (o un nome simile).

Se non lo vedi:

* controlla in **Project Settings → Plugins** che il plugin sia **abilitato**.

---

## 3) Com’è fatto il pannello (a cosa serve ogni sezione)

### A) Globale

**Omeka URL (default)**
Qui imposti l’indirizzo base del database Omeka S, ad esempio:

`https://omekas.livingculture.it`

Questo valore è un “default” usato come fallback.

✅ Quando serve: se una scena non ha ancora impostato il suo URL.

---

### B) Scena corrente (LivingScene)

Qui vedi lo stato della scena aperta e puoi impostare l’URL per quella scena.

* **Omeka URL (scena)**: l’URL usato dalla scena corrente.
* **Applica**: salva il valore nella scena.

✅ Consiglio: imposta sempre l’URL scena, così ogni scena “sa” dove puntare.

---

### C) Radice DB (LivingElement root)

Questa parte serve a definire la “radice” del database per la scena.

* **Root item_id**: è l’ID dell’oggetto Omeka che rappresenta la “radice” della scena (il tuo item principale).
* **Assicura root LivingElement**: crea (se manca) il nodo root LivingElement nella scena e imposta il suo item_id.

✅ In pratica: è il nodo da cui verranno “scoperti” i componenti (figli) dal DB.

---

### D) Azioni principali

Qui ci sono le operazioni più importanti:

#### 1) Aggiorna lista (DB)

Aggiorna il “magazzino” degli oggetti disponibili dal database (snapshot).

**Cosa fa:**

* aggiorna/ricarica le informazioni degli elementi già presenti in scena
* legge dal DB quali sono i **componenti** del root item (cioè gli oggetti “figli” del root sul database)
* popola la lista con **1 voce per oggetto** (unico per ID)

**Cosa NON fa:**

* non cambia il layout della scena
* non cancella o aggiunge oggetti in scena automaticamente
* non si aggiorna da sola quando piazzi oggetti

➡️ Usalo quando il DB è cambiato e vuoi aggiornare il magazzino.

---

#### 2) Istanzia scena da DB

Ricostruisce la scena “come è sul DB”.

**Cosa fa:**

* prende il root LivingElement reale in scena
* scarica info dal DB (Fetch)
* crea automaticamente i figli (Instantiate Components)
* avvia i download media per i figli (quando necessario)

➡️ Usalo quando vuoi che la struttura della scena rispecchi quella del database.

> Nota: non è pensato per fare layout, ma per importare/aggiornare “la struttura”.

---

#### 3) Reset / svuota layout

Svuota gli oggetti sotto la root LivingElement in scena.

**Cosa fa (attualmente):**

* rimuove tutti i LivingElement figli diretti della root

⚠️ Attenzione: è una pulizia “forte”.
Usala quando vuoi ripartire da zero con il layout.

---

#### 4) Auto layout

Dispone automaticamente gli oggetti in griglia (in base ai parametri).

**Cosa fa:**

* prende tutti i LivingElement figli della root
* li dispone in una griglia sequenziale (righe/colonne)

➡️ Utile per una prima sistemazione “ordinata”.

---

## 4) Lista oggetti (Magazzino) e Preview

### Cosa mostra la lista

La lista mostra gli oggetti “componenti” del root sul database (snapshot).

* Ogni riga: nome + `(#item_id)`
* L’immagine di anteprima al momento è una **placeholder** (icona), non una thumbnail reale.

### Importante: lista ≠ scena

* La lista NON rappresenta gli oggetti già presenti nella scena.
* Puoi piazzare lo stesso oggetto anche 2, 3, 10 volte: la lista non cambia.
* La lista cambia solo con **Aggiorna lista (DB)**.

---

## 5) Piazzare oggetti in scena (layout manuale)

### Parametri di piazzamento

Nella colonna a destra:

* **Cella** (es. `A1`, `A4`, `C2`)
  indica la posizione su una griglia.
* **Spacing**
  distanza tra le celle (quanto “larga” è la griglia).

### Come piazzare

1. Seleziona un oggetto nella lista
2. scrivi la cella (es. `A4`)
3. premi **Piazza come figlio del root**
   (oppure doppio click sull’oggetto in lista)

✅ Risultato: viene creato un nuovo LivingElement in scena con quell’item_id.

> Puoi piazzare duplicati: ogni click crea un nuovo nodo.

---

## 6) Workflow consigliato (passo-passo)

1. **Apri una scena** (con root `LivingScene`)
2. In **Globale**, imposta l’Omeka URL default (se non già fatto)
3. In **Scena corrente**, controlla l’URL e premi **Applica** se serve
4. Inserisci **Root item_id**
5. Premi **Assicura root LivingElement**
6. Premi **Aggiorna lista (DB)** per riempire il magazzino
7. Usa la lista per piazzare oggetti e costruire il layout
8. (Opzionale) premi **Auto layout** per sistemazione automatica
9. (Opzionale) premi **Istanzia scena da DB** se vuoi importare/aggiornare la struttura dal DB
10. (Se necessario) **Reset / svuota layout** per ripartire

---

## 7) Problemi comuni

### “Non vedo nulla / pulsanti disabilitati”

* probabilmente la scena non è un `LivingScene` come root.

### “La lista non cambia quando piazzo oggetti”

È normale: la lista è un magazzino dal DB, non la scena.

### “Voglio aggiornare il magazzino perché il DB è cambiato”

Premi **Aggiorna lista (DB)**.

### “Ho perso il layout / voglio tornare indietro”

Le azioni principali usano Undo/Redo di Godot quando possibile:

* prova `Ctrl+Z` / `Ctrl+Y`.

---

## 8) Glossario rapido (per capirci al volo)

* **Omeka URL**: indirizzo del database Omeka S
* **item_id**: identificatore numerico dell’oggetto su Omeka
* **LivingScene**: nodo root della scena Godot
* **LivingElement**: nodo che rappresenta un oggetto del DB
* **Components**: i figli del root sul DB (oggetti “contenuti” nella radice)
* **Magazzino (lista)**: snapshot degli oggetti disponibili dal DB
* **Layout**: disposizione spaziale degli oggetti in scena

---

Se vuoi, posso anche impaginarti questa guida in un formato “manuale” più bello (con schermate/icone) oppure preparare una versione molto breve “cheat sheet” di 1 pagina.
