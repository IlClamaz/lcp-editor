# A cosa serve, in pratica
`curator_dock` è un plugin editor pensato per chi deve preparare e aggiornare ambienti dentro Godot senza lavorare direttamente su tutta la logica tecnica.
 
Quando il plugin è attivo, compare un pannello laterale ("dock") che permette di:
* collegarsi a OmekaS;
* cercare gli ambienti disponibili;
* creare o sincronizzare una scena `LivingEnvironment`;
* vedere e gestire gli elementi già caricati (lista, thumbnail, visibilità, lock, posizione);
* assicurarsi che nella scena ci siano i pezzi minimi (camera, luci, pavimento).
 
In breve: il dock è la "console operativa" dei curatori.
 
# Struttura del plugin

## Entry point
* `addons/curator_dock/plugin.cfg`
* `addons/curator_dock/curator_plugin.gd`
 
`curator_plugin.gd` è il punto di ingresso (`EditorPlugin`). Si occupa di:
* creare il pannello (`curator_dock.gd`);
* passargli `EditorInterface` e `UndoRedo`;
* agganciarlo ai dock di Godot;
* gestire setup profili editor (Developer / Curator);
* fare cleanup quando il plugin viene disattivato.
 
## UI del dock
* `addons/curator_dock/docks/curator_dock.gd`
* `addons/curator_dock/docks/curator_dock_ui_builder.gd`
 
La UI è costruita interamente via codice.
`curator_dock.gd` contiene la logica operativa del pannello, mentre `curator_dock_ui_builder.gd` crea i controlli (campi URL, lista ambienti, pulsanti, tree inventory, anteprima, check stato, ecc.).
 
# I controller (chi fa cosa)

## `curator_scene_controller.gd`
Gestisce il rapporto con la scena aperta:
* verifica se il root editato è un `LivingEnvironment`;
* legge/salva URL Omeka globale in `EditorSettings`;
* applica quell'URL alla scena corrente;
* scansiona ricorsivamente l'ambiente e produce uno snapshot per la lista.
 
## `curator_inventory_controller.gd`
Gestisce la lista degli item nel dock:
* render del Tree a partire dallo snapshot;
* icone area/elemento;
* caricamento thumbnail con cache;
* selezione e ripristino selezione dopo refresh;
* risoluzione del nodo reale partendo da metadata (`instance_id` o `node_path`).
 
## `curator_setup_controller.gd`
Gestisce i componenti base della scena:
* `ensure_player`
* `ensure_floor`
* `ensure_lights`
 
Evita duplicati grazie a gruppi marker (`curator_player`, `curator_floor`, `curator_lights`) e usa Undo/Redo dove possibile.
 
## `curator_editor_hooks.gd`
Sincronizza eventi editor con il dock:
* cambi selezione nel `SceneTree`;
* aggiunta/rimozione nodi;
* eventi Undo/Redo;
* polling trasformazioni del nodo selezionato per aggiornare campi X/Z nel dock.
 
# Flusso tipico di lavoro
1. Apri Godot e attiva il plugin.
2. Nel dock imposti URL Omeka.
3. Premi "Aggiorna Lista" e il dock scarica gli ambienti da Omeka.
4. Selezioni un ambiente e premi "Carica / Sincronizza Ambiente".
5. Se non c'è una scena valida, viene creata da template in `res://curated_scenes`.
6. Viene impostato `item_id`, viene fatto rebuild dell'ambiente e parte il download dei media.
7. Usi la lista per controllare visibilità, lock, posizionamento e ordine.
 
# Instanziazione e tracking progresso

## `curator_environment_instatiator.gd`
Fa da orchestratore tecnico quando premi il pulsante di carica/sync:
* apre o crea la scena target;
* applica URL e `item_id`;
* assicura setup base;
* lancia `rebuild_environment()` su `LivingEnvironment`.
 
## `curator_download_progress.gd`
Monitora download media/thumbnail durante la sincronizzazione:
* conta pending download;
* emette progresso percentuale;
* chiude solo quando sia build che download sono finiti.
 
Questo evita che la UI segnali "completato" troppo presto.
 
# Funzioni importanti lato UX
* Toggle visibilità per riga (icona occhio).
* Toggle lock editing (icona lucchetto, meta `_edit_lock_`).
* "Riposiziona" su X/Z del nodo selezionato.
* "Reset rotazioni".
* Auto layout su figli `LivingElement` di una `LivingArea`.
* Reset ambiente (svuota contenuti dinamici e riporta `item_id` a 0).
 
# Dipendenze dal plugin core
`curator_dock` non è indipendente: usa classi e scene di `living_platform_plugin`.
 In particolare:
* root atteso: `LivingEnvironment`;
* nodi gestiti: `LivingItem`, `LivingArea`, `LivingElement`, `LivingScene`;
* template e scene di supporto prese da `addons/living_platform_plugin/scenes`.
 
# Limiti e attenzione pratica
* Se URL Omeka non è valido o la rete fallisce, il dock entra in stato errore e blocca alcune azioni.
* Il flusso è pensato per scene con root `LivingEnvironment`: su root diversi il dock non può lavorare correttamente.
* Il lock `_edit_lock_` è persistente in scena: può sembrare un bug se non lo si ricorda.
 
# In due righe
Se il `living_platform_plugin` è il motore dati/media, `curator_dock` è il pannello operativo che rende quel motore utilizzabile dal team editoriale dentro Godot, con workflow guidato e controlli sicuri.


---


# What it does, in practice
`curator_dock` is an editor plugin designed for those who need to prepare and update environments within Godot without working directly on the underlying technical logic.

When the plugin is active, a side panel ("dock") appears that allows you to:
* connect to OmekaS;
* search for available environments;
* create or synchronize a `LivingEnvironment` scene;
* view and manage already loaded elements (list, thumbnail, visibility, lock, position);
* ensure that the scene contains the minimum required components (camera, lights, floor).

In short: the dock is the "operational console" for curators.

# Plugin Structure

## Entry point
* `addons/curator_dock/plugin.cfg`
* `addons/curator_dock/curator_plugin.gd`

`curator_plugin.gd` is the entry point (`EditorPlugin`). It handles:
* creating the panel (`curator_dock.gd`);
* passing `EditorInterface` and `UndoRedo` to it;
* attaching it to Godot's docks;
* managing editor profile setups (Developer / Curator);
* performing cleanup when the plugin is deactivated.

## Dock UI
* `addons/curator_dock/docks/curator_dock.gd`
* `addons/curator_dock/docks/curator_dock_ui_builder.gd`

The UI is built entirely via code.
`curator_dock.gd` contains the panel's operational logic, while `curator_dock_ui_builder.gd` creates the controls (URL fields, environment list, buttons, inventory tree, preview, status checks, etc.).

# Controllers (who does what)

## `curator_scene_controller.gd`
Manages the relationship with the open scene:
* verifies if the edited root is a `LivingEnvironment`;
* reads/saves the global Omeka URL in `EditorSettings`;
* applies that URL to the current scene;
* recursively scans the environment and produces a snapshot for the list.

## `curator_inventory_controller.gd`
Manages the item list in the dock:
* renders the Tree starting from the snapshot;
* area/element icons;
* thumbnail loading with cache;
* selection and selection restoration after refresh;
* resolution of the real node starting from metadata (`instance_id` or `node_path`).

## `curator_setup_controller.gd`
Manages the base components of the scene:
* `ensure_player`
* `ensure_floor`
* `ensure_lights`

It avoids duplicates using marker groups (`curator_player`, `curator_floor`, `curator_lights`) and uses Undo/Redo where possible.

## `curator_editor_hooks.gd`
Synchronizes editor events with the dock:
* selection changes in the `SceneTree`;
* node addition/removal;
* Undo/Redo events;
* polling transformations of the selected node to update X/Z fields in the dock.

# Typical Workflow
1. Open Godot and activate the plugin.
2. Set the Omeka URL in the dock.
3. Press "Update List" and the dock downloads environments from Omeka.
4. Select an environment and press "Load / Sync Environment".
5. If there is no valid scene, one is created from a template in `res://curated_scenes`.
6. `item_id` is set, the environment is rebuilt, and media download starts.
7. Use the list to control visibility, lock, positioning, and order.

# Instantiation and Progress Tracking

## `curator_environment_instatiator.gd`
Acts as the technical orchestrator when you press the load/sync button:
* opens or creates the target scene;
* applies URL and `item_id`;
* ensures base setup;
* triggers `rebuild_environment()` on `LivingEnvironment`.

## `curator_download_progress.gd`
Monitors media/thumbnail downloads during synchronization:
* counts pending downloads;
* emits percentage progress;
* finishes only when both the build and the download are complete.

This prevents the UI from reporting "completed" too early.

# Important UX Features
* Visibility toggle per row (eye icon).
* Editing lock toggle (padlock icon, `_edit_lock_` meta).
* "Reposition" on X/Z of the selected node.
* "Reset rotations".
* Auto layout on `LivingElement` children of a `LivingArea`.
* Environment reset (clears dynamic contents and resets `item_id` to 0).

# Core Plugin Dependencies
`curator_dock` is not independent: it uses classes and scenes from `living_platform_plugin`.
Specifically:
* expected root: `LivingEnvironment`;
* managed nodes: `LivingItem`, `LivingArea`, `LivingElement`, `LivingScene`;
* template and support scenes taken from `addons/living_platform_plugin/scenes`.

# Limitations and Practical Warnings
* If the Omeka URL is invalid or the network fails, the dock enters an error state and blocks some actions.
* The workflow is designed for scenes with a `LivingEnvironment` root: on different roots, the dock cannot work correctly.
* The `_edit_lock_` lock is persistent in the scene: it might look like a bug if you don't remember setting it.

# In Two Lines
If `living_platform_plugin` is the data/media engine, `curator_dock` is the operational panel that makes that engine usable by the editorial team inside Godot, with a guided workflow and safe controls.