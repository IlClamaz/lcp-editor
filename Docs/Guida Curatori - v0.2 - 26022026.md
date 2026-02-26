Per aprire Godot (macOS): apri la cartella `mac/`, decomprimi la cartella `Godot_v4.5.1-stable_macos.universal`, poi fai doppio click su **Godot.app**. Se macOS blocca l’app (“sviluppatore non identificato”), fai **tasto destro → Apri → Apri** (solo la prima volta). 

Per aprire Godot (Windows): apri la cartella `windows/` e fai doppio click sul file `Godot_v4.5.1-stable_win64`.

---

Poi, in Godot premi **Importa**, seleziona la cartella `lcp-editor`, fai un solo click, quindi premi **Seleziona cartella corrente**.

> A questo punto dovresti avere Godot aperto e davanti una scena vuota (o una scena già basata su LivingEnvironment). La scena contiene un ambiente 3D senza oggetti e un pannello laterale con campi e icone, che d'ora in avanti chiameremo "dock". Se così non fosse, fermati e contatta gli sviluppatori.

# Guida Curatori — Living Culture Platform Editor v0.2 (Godot) - 26.02.2026 - Vittorio Murtas / Fabrizio Nunnari (vittorio.murtas@unito.it / fabrizio.nunnari@dfki.de)

## 1) Impostazioni

Imposta i seguenti campi prima di iniziare a lavorare. Nel caso in cui non fosse la prima volta che apri il progetto, vai direttamente al punto 3. 
⚠️ Nota: Ogni operazione che troverai in questo documento, dal punto 3 in poi, è ANNULLABILE. Quindi ti basta premere **⌘Z** (mac) o **CTRL+Z** (windows) per tornare a uno stato precedente all'applicazione dell'operazione.

### Campo **Omeka**
Inserisci la base URL del database (ad esempio, `https://omekas.livingculture.it`):   
Per il momento, inserisci: `https://omekadev.livingculture.it`

### Campo **Environment ID**
Inserisci l’ID numerico dell’ambiente nel database (ad es. `1687` per l'ambiente dello zootropio gigantismo). Per il futuro ci sarà una lista con tutti gli ambienti disponibili sul database da cui scegliere.
Per il momento, inserisci: `1687` (Gigantismo) o `1696` (Plaza Cabiria)

Regola importante:
- **senza un ID valido non è possibile istanziare l’ambiente.** In caso di ID non esistente che non fa riferimento a un Environment, verrà mostrato un messaggio di errore alla pressione del tasto Istanzia Ambiente.

---

## 2) Istanzia ambiente

### Pulsante **Istanzia ambiente**
Serve a creare e costruire l’ambiente in scena. Se l'id inserito corrisponde a un ambiente sul database, sarà visibile un'etichetta accanto al bottone che mostra il progresso di istanziazione e la lista (inventory) si popolerà. Al termine del progresso (100%), gli oggetti scaricati saranno visibili in scena. L'etichetta di progresso mostra anche l'esito dell'ultima istanziazione: in caso positivo apparirà "Completato", altrimenti "Errore". 

⚠️ Nota: il bottone indica che “sovrascrive” l’ambiente se già istanziato. Significa che ricostruisce la struttura dall’ID inserito. Quindi, premerlo con cautela una volta che tutti gli oggetti sono già in scena, perché verrebbero sovrascritti da quelli presi dal database. QUESTA AZIONE NON SI PUO' ANNULLARE!!

---

## 3) Sanity Check (controllo rapido)

Sotto “Sanity Check” trovi 4 indicatori:

- **Camera**: ✅ / ❌
- **Luci**: ✅ / ❌
- **Pavimento**: ✅ / ❌
- **Ambiente**: ✅ / ❌ (dipende se l’Environment ha un item_id valido o se è in fase di istanziazione)

Come interpretarlo:
- Se mancano Luci, Camera o Pavimento (perché magari li hai per sbaglio eliminati), puoi aggiungerli con i pulsanti “Assicura …”.
- Se l'ID è corretto e l'URL è corretto, ma ambiente non mostra ✅ potrebbe esserci un problema con la rete: non usare eduroam (a volte può dare problemi anche unito-wifi), cercare una rete alternativa.

---

## 4) Lista (Inventory) — come usarla

### Cosa mostra
La lista rappresenta lo **stato corrente della scena**:
- 👁️ = nodo visibile
- 🚫 = nodo nascosto
- indentazione = livello gerarchico nell’albero
- thumbnail = un'immagine d'anteprima del media (modello 3D, immagine, video...): in caso di thumbnail mancante sul database, viene mostrata un'icona con una A per le `LivingArea`, mentre una con una E per i `LivingElement`.

### Click (selezione)
- **Click singolo** su un elemento:
  - seleziona l’elemento nella scena
  - vedrai i **gizmo** (le freccette / curve colorate) nel viewport 3D
  - vedrai la **thumbnail** nel pannello a fianco alla lista

### Doppio click (visibilità)
- **Doppio click** su un elemento:
  - alterna visibile/nascosto (toggle visibility)

---

## 5) Riposizionamento (Trasformazioni di traslazione e rotazione)

Gli oggetti sono cliccabili (selezionabili) o dalla scena o dalla lista (inventory). Una volta selezionati, gli oggetti sono spostabili / ruotabili tramite le freccette/curve colorate (chiamate gizmo) che si vedono nella scena e sono situati al centro dell'oggetto. Traslazione e rotazione sono gestibili anche tramite i seguenti pulsanti, situati sotto il pannello delle thumbnail:  

### Offset dall’origine (Traslazione Orizzontale / Profondità)
Sono coordinate (in globale) usate per spostare un oggetto in modo semplice, senza usare i gizmo:
- **X** = spostamento orizzontale, lungo l'asse X, la freccetta/asse rossa
- **Z** = spostamento “in profondità”, lungo l'asse Z, la freccetta/asse blu
- Y (la verticale, sull'asse verde) non viene cambiata

### Pulsante **Riposiziona**
- seleziona un item nella lista (o nella scena)
- imposta X e Z
- premi **Riposiziona**  
→ l’oggetto viene spostato a quelle coordinate (in globale). Ad esempio se si impostano con 0,0 sarà riposizionato all'origine della scena.

### Pulsante **Reset Rotazioni**
- seleziona un item nella lista (o nella scena)
- premi **Reset Rotazioni**  
→ l’oggetto viene ruotato alle sue coordinate originarie (0,0,0) (in globale)

---

## 6) Pulsanti pericolosi

### Auto Layout (Posiziona in griglia)
Parametri:
- **Distanza tra gli oggetti** = spacing
- **Oggetti per riga** = numero colonne

Cosa fa:
- Applica un layout a griglia **solo** ai `LivingElement` **figli diretti** di una `LivingArea`.
- Il pulsante è abilitato solo quando si seleziona dalla lista o dalla scena una `LivingArea`.

### Distruggi tutto (Svuota scena)
Rimuove tutti i `LivingItem` (aree ed element) figli del `LivingEnvironment`.

---

## 7) Assicura Camera / Pavimento / Luci

Questi pulsanti:
- creano i componenti mancanti
- **non** duplicano se sono già presenti

Usali quando nel Sanity Check vedi ❌.

---

## 8) Dare "play" (lanciare) la simulazione della scena

In alto a destra nell'editor, accanto al tasto "play" è presente l'icona di un piccolo "ciak":
- selezionare la prima icona con il ciak (quella con un play al centro) 
- esegui in modalità regolare (o xr nel caso si avesse un visore collegato al pc)

---

## 9) Workflow consigliato (rapido)

1) Inserisci **Omeka URL** (se necessario)
2) Inserisci **Environment ID**
3) Premi **Istanzia ambiente**
4) Controlla il **Sanity Check** (tutto ✅), a questo punto la lista dovrebbe essersi riempita
5) Lavora dalla lista:
   - click per selezionare (gizmo)
   - doppio click per mostrare/nascondere
   - usa X/Z + Riposiziona per spostare + Reset Rotazioni
7) Se serve, seleziona un elemento della lista, imposta distanza fra oggetti e oggetti per riga, e fai **Auto Layout**
8) Salva la scena con **⌘S** (mac) o **CTRL+S** (windows), apparirà un popup di successo e la troverai nella cartella `curated_scenes` del progetto. Eventualmente, puoi premere con il tasto destro sul nome della scena (in alto a sinistra es. `env_1687_2026...`) e premere “salva la scena come...” per rinominarla come preferisci.
9) Eventualmente lancia la scena ed esplorala in realtà virtuale (non immersiva o immersiva)

---

