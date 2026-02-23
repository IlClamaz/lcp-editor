Per aprire Godot: fare doppio click sul file `windows/Godot_v4.5.1-stable_win64`. Poi, premere su Importa e selezionare la cartella lcp-editor, poi Importa. 

# Guida Curatori — Living Culture Platform Editor v1.0 - 23.02.2026

Questa guida spiega come usare il **Curator Dock** dentro Godot per:
- impostare URL e ID dell’**Environment** (dal database Omeka)
- creare/istanziare un ambiente a partire dal template
- verificare rapidamente che **Camera / Luci / Pavimento / Ambiente** siano presenti (Sanity Check)
- navigare l’albero degli oggetti tramite la lista, selezionare i nodi e vedere i gizmo
- **mostrare/nascondere** elementi e **riposizionarli** con offset X/Z
- usare **Auto Layout** e **Svuota scena** (azioni “pericolose” ma undoabili)

> Presupposto: hai Godot aperto con il plugin già abilitato e davanti una scena vuota (o una scena già basata su LivingEnvironment).

---

## 1) Dove si trova il Curator Dock

Nel pannello laterale dell’Editor trovi un dock chiamato **Curator**.

---

## 2) URL (Omeka)

### Campo **Omeka**
Inserisci la base URL del database (esempio):  
`https://omekas.livingculture.it`
Per il momento, usa: `https://omekadev.livingculture.it` (già impostato di default)

Cosa succede:
- il valore viene salvato come **impostazione globale** dell’editor
- quando una scena con **LivingEnvironment** è attiva, l’URL viene applicato automaticamente all’ambiente

---

## 3) ID (Environment)

### Campo **Environment ID**
Inserisci l’ID numerico dell’ambiente nel database (es. `1687` - questo è l'ambiente dello zootropio gigantismo). Per il futuro ci sarà una lista con tutti gli ambienti disponibili sul database da cui scegliere. 

Regola importante:
- **senza un ID valido (> 0) non è possibile istanziare l’ambiente.** In caso di ID non esistente (ma > 0) o che non fa riferimento a un Environment, verrà mostrato un messaggio di errore alla pressione del tasto Istanzia Ambiente. 

---

## 4) Istanzia ambiente

### Pulsante **Istanzia ambiente**
Serve a creare e costruire l’ambiente in scena.

Comportamento:
- Se la scena corrente **non** ha un root `LivingEnvironment`, il plugin:
  1) crea una nuova scena, la apre e la salva dentro: `res://curated_scenes`
- Se la scena ha già un `LivingEnvironment`, procede direttamente.

Poi:
- applica l’URL Omeka all’ambiente
- assicura i componenti base (camera/player, luci, pavimento)
- chiama la procedura di rebuild dell’ambiente dal DB

⚠️ Nota: il bottone indica che “sovrascrive” l’ambiente se già istanziato. Significa che ricostruisce la struttura dall’ID inserito.

---

## 5) Sanity Check (controllo rapido)

Sotto “Sanity Check” trovi 4 indicatori:

- **Camera**: ✅ / ❌ (call devs)
- **Luci**: ✅ / ❌
- **Pavimento**: ✅ / ❌
- **Ambiente**: ✅ / ⚠ (dipende se l’Environment ha un item_id valido)

Come interpretarlo:
- Se vedi **❌ (call devs)** su Camera, è meglio fermarsi e avvisare gli sviluppatori (in genere manca un setup fondamentale).
- Se manca Luci o Pavimento, puoi aggiungerli con i pulsanti “Assicura …”.
- Se l'ID è corretto e l'URL è corretto, ma ambiente non mostra ✅ potrebbe esserci un problema con la rete: non usare unito-wifi o eduroam, cercare una rete alternativa. 

---

## 6) Lista (Inventory) — come usarla

### Cosa mostra
La lista rappresenta lo **stato corrente della scena**:
- 👁️ = nodo visibile
- 🚫 = nodo nascosto
- indentazione = livello gerarchico nell’albero

### Click (selezione)
- **Click singolo** su un elemento:
  - seleziona l’elemento nella scena
  - vedrai i **gizmo** nel viewport 3D
  - vedrai la **thumbnail** nel pannello a fianco alla lista 

### Doppio click (visibilità)
- **Doppio click** su un elemento:
  - alterna visibile/nascosto (toggle visibility)
  - l’azione è undoabile: **Ctrl+Z** ripristina

---

## 7) Thumbnail e comandi a destra

### Offset dall’origine (Orizzontale / Verticale)
Sono coordinate (in globale) usate per spostare un oggetto in modo semplice:
- **X** = spostamento orizzontale, lungo l'asse X
- **Z** = spostamento “in profondità”, lungo l'asse Z (verticale)
- Y non viene cambiata

### Pulsante **Riposiziona**
- seleziona un item nella lista
- imposta X e Z
- premi **Riposiziona**
→ l’oggetto viene spostato a quelle coordinate (in globale)

Undo:
- il riposizionamento è undoabile con **Ctrl+Z**.

---

## 8) Pulsanti pericolosi

### Auto Layout (Posiziona in griglia)
Parametri:
- **Distanza tra gli oggetti** = spacing
- **Oggetti per riga** = numero colonne

Cosa fa:
- Applica un layout a griglia **solo** ai `LivingElement` **figli diretti** del contenitore selezionato.
- Il “contenitore” viene scelto così:
  - se selezioni una **LivingArea** in lista → layout sui suoi figli diretti
  - altrimenti → layout sui figli diretti del **LivingEnvironment**
  - se selezioni un **LivingElement**, applica il layout a se stesso ed eventuali fratelli (figli della stessa area o environment, nel caso di oggetti di primo livello).

💡 Consiglio: seleziona prima l’Area (se vuoi impaginare solo quell’area).

Undo:
- Auto Layout è undoabile con **Ctrl+Z**.

### Distruggi tutto (Svuota scena)
Rimuove tutti i `LivingItem` figli diretti del `LivingEnvironment`.

Importante:
- Ctrl+Z ripristina i nodi rimossi.

---

## 9) Assicura Camera / Pavimento / Luci

Questi pulsanti:
- creano i componenti mancanti
- **non** duplicano se sono già presenti

Usali quando nel Sanity Check vedi ❌.

---

## 10) Workflow consigliato (rapido)

1) Inserisci **Omeka URL** (se necessario)
2) Inserisci **Environment ID**
3) Premi **Istanzia ambiente**
4) Controlla il **Sanity Check** (tutto ✅), a questo punto la lista dovrebbe essersi riempita
5) Lavora dalla lista:
   - click per selezionare (gizmo)
   - doppio click per mostrare/nascondere
   - usa X/Z + Riposiziona per spostare
7) Se serve, seleziona un elemento della lista, imposta distanza fra oggetti e oggetti per riga, e fai **Auto Layout**
8) Salva la scena con CTRL+S, la troverai nella cartella curated_scenes del progetto. Eventualmente, puoi premere con il tasto destro sul nome della scena (in alto a sinistra es. env_1687_2026...) e premere "salva la scena come..." per rinominarla come preferisci.

---
