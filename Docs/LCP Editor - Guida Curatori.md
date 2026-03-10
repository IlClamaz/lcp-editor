# Guida Curatori — Living Culture Platform (LCP) Editor v0.4 (Godot)

_Aggiornata a Marzo 2026 - Vittorio Murtas / Fabrizio Nunnari (vittorio.murtas@unito.it / fabrizio.nunnari@dfki.de)_

L'LCP Editor è lo strumento con cui i curatori preparano e rifiniscono gli ambienti espositivi di Living Culture Platform in Godot.
Permette di sincronizzare contenuti dal database, organizzare opere e media nella scena 3D e verificare rapidamente che tutto sia pronto per l'esplorazione.

**Per avviare Godot:**

- **macOS:** Apri la cartella `mac/`, decomprimi `Godot_v4.5.1-stable_macos.universal`, poi fai doppio click su `Godot.app`. Se macOS blocca l’app (“sviluppatore non identificato”), fai _Tasto destro → Apri → Apri_ (solo la prima volta).
    
- **Windows:** Apri la cartella `windows/` e fai doppio click sul file `Godot_v4.5.1-stable_win64`.

All'avvio, premi **Importa**, seleziona la cartella `lcp-editor`, fai un solo click, quindi premi **Seleziona cartella corrente**.

Una volta aperto Godot avrai davanti solo due cose:

1. **La Scena (al centro):** L'ambiente 3D in cui visualizzerai e sposterai gli oggetti.
2. **Il Pannello "Curator" (a destra):** Il centro di comando ("dock") da cui gestirai tutto il lavoro.

> ⚠️ **Nota:** Ogni operazione di spostamento, rotazione o modifica descritta in questo documento **ESCLUSO il "distruggi tutto" (punto 6)** è **ANNULLABILE**. Ti basta premere `⌘Z` (Mac) o `CTRL+Z` (Windows) per tornare indietro se commetti un errore.

---

### 0) Navigazione base della scena 3D (per iniziare)

Se non sei abituato ai programmi 3D, usa questi comandi base nella viewport:

- **Ruota la vista (orbita):** `Alt + tasto sinistro` e trascina.
- **Sposta la vista (panning):** `Alt + tasto centrale` e trascina.
- **Zoom:** usa la **rotella del mouse** (oppure `Alt + tasto destro` e trascina avanti/indietro).
- **Focus su un oggetto:** seleziona l'oggetto nella lista e premi `F` per centrare subito la camera su quell'elemento.

Se "ti perdi" nella scena, il comando `F` è il modo piu rapido per ritrovare l'oggetto su cui stai lavorando.

---

### 1) Connessione e Scelta dell'Ambiente

Prima di scaricare gli oggetti, dobbiamo dire al programma dove cercarli e quale ambiente vogliamo allestire.

- **Campo URL:** Inserisci l'indirizzo del database. Per ora usa: `https://omekadev.livingculture.it`
    
- **Selezione Ambiente:**
    2. Apri il menu a tendina (che inizialmente dice _" Seleziona un ambiente o aggiorna la lista..."_) e scegli quello su cui vuoi lavorare (es. _1687 - Zootropio Gigantismo_).
    3. Se la lista è vuota, premi il pulsante **Aggiorna Lista**. Il sistema si collegherà al database per cercare tutti gli ambienti disponibili.

---

### 2) Sincronizza / Carica Ambiente

Il pulsante principale del pannello avvia la comunicazione con il database. Quando premi il tasto:

- Se è la prima volta, scaricherà tutti i modelli 3D e i media, costruendo l'ambiente da zero.
- Se l'ambiente è già in scena, **NON cancellerà il tuo lavoro**. Il sistema controllerà il database: scaricherà solo i file che sono stati aggiornati di recente su internet e lascerà intatti gli oggetti che hai già posizionato con cura nella scena.

Accanto al bottone vedrai un'etichetta di stato. Al termine dirà **"Completato"**. Se la connessione cade o l'indirizzo è sbagliato, apparirà **"Errore di rete"**.

---

### 3) La Lista Oggetti

La lista mostra l'elenco di tutte le opere, video, testi e aree presenti nella tua scena. Cliccando su un elemento vedrai la sua immagine di anteprima (thumbnail) nel riquadro sottostante.

Oltre a selezionare gli oggetti, la lista ha due pulsanti interattivi su ogni riga:

- 👁️ **(Occhio):** Mostra o nasconde temporaneamente l'oggetto dalla scena. La prima volta che istanzierai l'ambiente, gli elementi mostreranno gli occhi tutti chiusi (nascosti). Saranno visibile solo il template (che non appare nella lista) e le aree. Se premi l'occhio su un'area, vengono nascosti anche gli elementi figli dell'area. Quando "chiudi" l'occhio, l'oggetto su cui hai la selezione verrà deselezionato. Se lo selezionerai in futuro, ricordati di "riaprire" l'occhio (per vederlo in scena) prima di muoverlo. 
- 🔒 **(Lucchetto):** Blocca l'oggetto. Un oggetto bloccato **non può essere selezionato o spostato per sbaglio** cliccandoci sopra nella visuale 3D. Usalo quando hai posizionato un'opera esattamente dove vuoi e non vuoi rischiare di muoverla inavvertitamente.

---

### 4) Riposizionamento e Trasformazioni

Per muovere gli oggetti hai due opzioni:

**A. Manualmente dalla scena 3D (Gizmo)**

Seleziona un oggetto dalla lista (assicurati che non abbia il lucchetto chiuso). Al centro dell'oggetto appariranno delle frecce e delle curve colorate (i "Gizmo"):
- Trascina le **frecce** per spostarlo.
- Trascina le **curve** per ruotarlo.

**B. Tramite il Pannello**

Sotto l'immagine di anteprima troverai i comandi per le coordinate Globali:

- **X:** Spostamento orizzontale (asse rosso).
- **Z:** Spostamento in profondità (asse blu).
- L'altezza (Y, asse verde) viene mantenuta automatica per far poggiare le opere a terra.
- Digita i numeri e premi **Riposiziona** per applicare lo spostamento esatto.
- Premi **Reset Rotazioni** per raddrizzare un oggetto e riportarlo alla sua rotazione originale (0,0,0).

---

### 5) Sanity Check (Controllo Rapido & Soluzione)

Questa sezione ti assicura che la scena abbia tutto il necessario per funzionare correttamente in Realtà Virtuale. Troverai 4 indicatori:

- **Camera:** ✅ / ❌ (Il punto di vista del visitatore)
- **Luci:** ✅ / ❌ (L'illuminazione generale)
- **Pavimento:** ✅ / ❌ (L'area su cui il visitatore può camminare)
- **Ambiente:** ✅ / ❌ (Verifica che i dati scaricati siano corretti)

---

### 6) Pulsanti pericolosi

- **Auto Layout (Disposizione in griglia):** Seleziona una _LivingArea_ (una zona che raggruppa più elementi) e imposta la "Distanza" e le "Colonne". Premendo questo tasto, tutti gli oggetti contenuti in quell'area verranno ordinati automaticamente in una griglia geometrica perfetta.
    
- **Svuota Scena (Distruggi tutto):**
    Rimuove tutti gli oggetti scaricati dall'ambiente, ripulendo la stanza. Utile se vuoi ricominciare da capo (questa operazione riporterà la spunta dell'Ambiente a ❌ nel Sanity Check finché non sincronizzerai di nuovo). ATTENZIONE: QUESTA OPERAZIONE NON SI PUO' ANNULLARE

---

### 7) Esplorare l'ambiente (Play)

In alto a destra nell'editor c'è l'icona di un piccolo "ciak" con il simbolo Play al centro.

Premilo per avviare la simulazione della scena e camminare nell'ambiente che hai creato.

---

### 8) Workflow di Lavoro Consigliato

1. Inserisci l'URL di Omeka (di default è già impostato).
2. Seleziona il tuo ambiente dal menu a tendina. In caso fosse vuoto, premi **Aggiorna Lista**.
3. Premi **Sincronizza Ambiente** e attendi il "Completato" (100%).
4. Lavora dalla lista:
    - Seleziona gli oggetti per far apparire i Gizmo e spostarli nel 3D.
    - Chiudi il lucchetto (🔒) per le opere che hai già sistemato definitivamente.
    - Usa i comandi _X/Z + Riposiziona_ per gli allineamenti di precisione.
5. **Salva il tuo lavoro** premendo `⌘S` (Mac) o `CTRL+S` (Windows).
6. Premi il tasto **Play** in alto a destra per esplorare il tuo allestimento.
