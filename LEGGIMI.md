# Algor Bomber — guida per metterla online

Servono tre account gratuiti: **GitHub**, **Supabase**, **Vercel**. Tempo: circa 20 minuti.
Il sito è la cartella `web` (questa). Il resto dello zip (`sorgenti`) serve solo per le modifiche future.

## 1. Il database (Supabase)
1. Vai su supabase.com → **New project**. Scegli un nome (es. `algor-bomber`), una password per il database (salvala) e una regione europea.
2. Quando il progetto è pronto apri **SQL Editor** → **New query**, incolla tutto il contenuto di `supabase/schema.sql` e premi **Run**. Deve comparire "Success". Poi, ognuno in una nuova query e in quest'ordine, fai lo stesso con `supabase/aggiornamento-gruppi.sql` (gruppi, chat, amministrazione) con `supabase/aggiornamento-iscritti.sql` (iscritti visibili a tutti, stats generali, aggiunta ai gruppi) con `supabase/aggiornamento-partite.sql` (comune dei gruppi, modifica del gruppo, sondaggio sul giorno) con `supabase/aggiornamento-amici.sql` (amicizie) con `supabase/aggiornamento-traguardi.sql` (traguardi di tutti), con `supabase/aggiornamento-chat.sql` (chat come WhatsApp; per le notifiche serve anche la funzione `notify`, vedi più sotto) con `supabase/aggiornamento-notifiche.sql` (notifiche delle partite, link d'invito, pronostici) con `supabase/aggiornamento-valutazioni.sql` (valutazioni che si sommano, Confronto, traguardi di chi valuta) con `supabase/aggiornamento-panchina.sql` (notifica a chi va in panchina dal Campo) e con `supabase/aggiornamento-regole.sql` (le regole delle partite controllate anche dal database).
3. **Authentication → Providers → Email**: lascia attivo l'accesso con email e **disattiva "Confirm email"** (così gli amici entrano subito senza aspettare la mail).
4. **Project Settings → API**: copia **Project URL** e la chiave **anon public**.
5. Apri il file `config.js` di questa cartella e incolla i due valori al posto delle scritte `INCOLLA_QUI_…`. (La chiave anon può stare nel sito: la sicurezza la fanno le regole del database.)

## 2. Il codice (GitHub)
1. Su github.com crea un repository nuovo (es. `algor-bomber`), privato va bene.
2. **Add file → Upload files** e trascina **il contenuto della cartella `web`** (index.html, config.js, sw.js, manifest, icone, cartella supabase). Premi **Commit**.

## 3. Il sito (Vercel)
1. Su vercel.com accedi con GitHub → **Add New → Project** → scegli il repository `algor-bomber` → **Deploy** (nessuna impostazione da cambiare: è un sito statico).
2. Al termine ottieni un indirizzo tipo `calcetto-xxxx.vercel.app`. È il link da mandare agli amici. Il nostro è **algor-bomber.vercel.app**: è l'unico indirizzo dell'app (vedi "Versione, aggiornamenti e indirizzo unico").
3. Torna su Supabase → **Authentication → URL Configuration** e incolla quell'indirizzo in **Site URL** e in **Redirect URLs** (servono ai link "password dimenticata" e di conferma dell'iscrizione).

## 4. Installarla sul telefono
- **Android (Chrome):** apri il link → menu ⋮ → **Installa app** (o "Aggiungi a schermata Home").
- **iPhone (Safari):** apri il link → Condividi → **Aggiungi a schermata Home**.
Ha la sua icona e si apre a schermo intero.

## Aggiornare l'app per tutti
Quando ti mando una versione nuova, sostituisci i file su GitHub (**Add file → Upload files**, stessi nomi, **Commit**). Vercel pubblica da solo in un minuto. L'app sul telefono si apre subito con la versione che ha, intanto vede quella nuova e mostra in alto **«Nuova versione pronta — Aggiorna»**; se nessuno tocca Aggiorna, parte la volta dopo che si apre l'app da chiusa. I dati nel database restano.
Non sovrascrivere `config.js` con quello vuoto: tieni il tuo.

## Dove stanno i dati
Giocatori, partite, voti, gruppi e messaggi stanno nel database **Supabase**, non su GitHub. GitHub contiene solo il codice dell'app: è da lì che Vercel prende gli aggiornamenti, quindi conviene tenerlo, ma cancellare o cambiare i file su GitHub non tocca i dati.

## Aggiornamento di ottobre 2026: gruppi, messaggi, menu
Va fatto **una volta sola, prima** di pubblicare il nuovo `index.html`:
1. Supabase → **SQL Editor** → **New query**, incolla tutto `supabase/aggiornamento-gruppi.sql` e premi **Run**.
2. Deve comparire una riga con "Aggiornamento completato", il numero di documenti salvati nella copia e i membri del primo gruppo.

Lo script per prima cosa salva una copia completa dei dati nella tabella `backup.docs_20261029` (visibile in Table Editor, schema `backup`). Poi crea il gruppo "Algor Bomber" (La Spezia) con tutti gli iscritti di oggi, sposta dentro il gruppo partite, valutazioni e voti MVP, e aggiunge le regole per gruppi, chat, help e amministrazione. Si può rilanciare senza danni.
Gli amministratori dell'app sono nella tabella `app_admins` (per aggiungerne uno: `insert into app_admins (email) values ('nome@esempio.it');`).

## Aggiornamento di ottobre 2026 (seconda parte): iscritti e aggiunta ai gruppi
Una volta sola: Supabase → **SQL Editor** → **New query**, incolla tutto `supabase/aggiornamento-iscritti.sql` e premi **Run**; deve comparire "Aggiornamento completato" con il numero di iscritti e di gruppi. Non sposta e non cancella dati.
Da qui in poi tutti gli iscritti vedono i profili di tutti, le stats generali sono la media dei voti di tutti i gruppi (senza dire chi li ha dati) e gli amministratori di un gruppo possono aggiungere direttamente un iscritto.

## Aggiornamento di ottobre 2026 (terza parte): zone
Una volta sola: Supabase → **SQL Editor** → **New query**, incolla tutto `supabase/aggiornamento-zone.sql` e premi **Run**; deve comparire "Aggiornamento completato". Non sposta e non cancella dati.
I gruppi salvano il comune scelto dall'elenco (`comuni.json`, dati ISTAT) con le sue coordinate, così si cercano per distanza; gli amministratori del gruppo possono cambiarne nome e città. La posizione delle persone non viene mai chiesta: conta solo il comune che scelgono nel profilo.

## Aggiornamento di ottobre 2026 (quarta parte): partite
Una volta sola: Supabase → **SQL Editor** → **New query**, incolla tutto `supabase/aggiornamento-partite.sql` e premi **Run**; deve comparire "Aggiornamento completato". Contiene anche le funzioni di `aggiornamento-zone.sql`, quindi basta questo. Non sposta e non cancella dati.
Aggiunge il sondaggio sul giorno: ognuno segna i giorni in cui è libero e, appena un giorno arriva al numero per due squadre piene, la partita nasce da sola con chi l'ha votato (il voto e la chiusura li fa il database, così due voti nello stesso momento non creano due partite).

## Aggiornamento di ottobre 2026 (quinta parte): amici
Una volta sola: Supabase → **SQL Editor** → **New query**, incolla tutto `supabase/aggiornamento-amici.sql` e premi **Run**; deve comparire "Aggiornamento completato". Non sposta e non cancella dati.
Aggiunge le amicizie (richiesta da accettare; le vedono solo le due persone) e toglie le amicizie insieme all'account quando lo si elimina. L'affinità tra compagni la calcola l'app dalle partite giocate.

## Card, traguardi e meteo
Non serve niente sul database. Il meteo dei giorni delle partite arriva da Open-Meteo (gratuito per uso non commerciale, previsioni fino a 16 giorni), usando la posizione del campo o il comune del gruppo; la posizione delle persone non viene mai chiesta.

Nel profilo i traguardi sono in vetrina: si vedono i nuovi e i più importanti (oro, poi argento, poi bronzo), al massimo 4; con **Vedi tutti** si apre la pagina con tutti gli stemmi, divisi per tipo.

## Scivolata in Difesa
Non serve niente sul database. La Difesa ora ha tre voci: Contrasto, Scivolata e Posizionamento (in tutto 17 voci). Nelle valutazioni date prima la Scivolata non c'è: nei conti vale la media di Contrasto e Posizionamento di quella valutazione, quindi nessun punteggio cambia finché qualcuno non la vota davvero. Chi era già iscritto, aprendo l'app, dà una volta sola la propria Scivolata (il resto dell'autovalutazione resta com'era e resta bloccato).

## Card da condividere, locandina, effetti, podio, campo e numero di maglia
Non serve niente sul database. Ognuno può condividere come immagine solo la propria card; dalla partita si condividono la locandina (giorno, campo, formazioni) e il risultato (marcatori e MVP), con i soprannomi e senza foto. Le immagini si preparano sul telefono, non passano da nessun server. Il numero di maglia (facoltativo, da 1 a 99) si sceglie in Modifica profilo. La card a tutto schermo entra girando e le stats compaiono con una luce che si diffonde; lo scudo è più elaborato salendo di livello (bronzo, argento, oro, MVP). Gli effetti (animazioni, raggi nei momenti speciali, coriandoli) si spengono da soli se sul telefono è attivo "Riduci movimento".

## Traguardi di tutti (supabase/aggiornamento-traguardi.sql)
Chiunque vede i traguardi di chiunque dal suo profilo. Nella vista "Nel gruppo" contano le partite del gruppo; nella vista "Generali", e per chi non è nel tuo gruppo, contano tutte le partite in tutti i gruppi. Per questi ultimi serve una funzione nuova del database: in Supabase apri **SQL Editor**, incolla tutto il contenuto di `supabase/aggiornamento-traguardi.sql` ed esegui (Run). Deve comparire "Aggiornamento traguardi completato". Non modifica né cancella dati: aggiunge solo due funzioni di lettura, che restituiscono i dati di quella persona senza dire chi sono i compagni né quali sono i gruppi. Finché non lo esegui, l'app mostra i traguardi del gruppo per i compagni e un avviso per gli altri.

**Novembre 2026:** lo script ha una funzione in più, `friend_count`, che dice a chiunque quanti amici ha una persona (solo il numero e al massimo 5, mai chi sono): serve perché il traguardo "Compagnia" (5 amici) si veda anche nei profili degli altri. Chi l'aveva già eseguito lo riesegue una volta (si può rieseguire senza problemi). Finché non lo riesegui, "Compagnia" si vede solo nel proprio profilo e gli altri contano 25 traguardi invece di 26.

## Chat come WhatsApp (supabase/aggiornamento-chat.sql e funzione notify)
La scheda Messaggi ha le chat dei gruppi e le chat private tra compagni di gruppo o amici (le leggono solo le due persone, nemmeno gli amministratori dell'app). Si mandano foto (ridotte sul telefono a circa 300 KB), GIF e sticker, emoji e vocali; si risponde a un messaggio, si reagisce, si inoltra in un'altra chat, si modifica nei primi 15 minuti, si elimina per tutti; ci sono le spunte, «sta scrivendo…», le menzioni con @ e le notifiche sul telefono. Niente video, per non riempire lo spazio gratuito (1 GB): gli amministratori dell'app vedono quanto spazio usano foto e vocali in Amministrazione.

1. **Database** (una volta sola): Supabase → **SQL Editor** → **New query**, incolla tutto `supabase/aggiornamento-chat.sql` e premi **Run**; deve comparire "Aggiornamento chat completato". Non sposta e non cancella dati; si può rieseguire. Finché non lo esegui, nella chat si scrive solo testo.
2. **Notifiche** (una volta sola): Supabase → **Edge Functions** → **Deploy a new function** → **Via Editor**. Nome: `notify`. Cancella l'esempio, incolla tutto `supabase/functions/notify/index.ts` e premi **Deploy**. Poi, nella pagina della funzione, apri **Settings** (o Details), spegni **Enforce JWT verification** / **Verify JWT** e salva: chi chiama lo controlla la funzione stessa. Non servono segreti: le chiavi delle notifiche le crea la funzione la prima volta e le tiene nel database.
3. Ognuno attiva le notifiche dal proprio telefono: scheda Messaggi (riquadro "Attiva le notifiche") o menu ☰ → Impostazioni → Notifiche, dove c'è anche "Manda una prova". Su iPhone funzionano solo con l'app aggiunta alla schermata Home (Safari → Condividi → Aggiungi alla schermata Home) e aperta da lì.
4. **GIF e sticker** (facoltativo): servono una chiave gratuita di KLIPY (partner.klipy.com → API Keys) da mettere in `config.js` alla voce `klipyKey`. Senza chiave si possono comunque mandare le GIF salvate nel telefono dalla Galleria.

## Novità di fine ottobre 2026: feste, cassa, maglie, temi, home (solo `index.html`)
Non serve niente sul database: basta caricare `index.html`.
- **Addobbi delle feste** (Halloween, neve dall'8 dicembre al 6 gennaio, Natale, Capodanno, Befana, Carnevale, San Valentino, Pasqua e Pasquetta, Ferragosto): si spengono in Impostazioni → Aspetto.
- **Cassa e campo prenotato** nei Dettagli della partita; chi deve pagare lo trova tra le cose da fare.
- **Maglie del mese** (rosa, ciclamino, azzurra, bianca) nello Storico, alla voce Maglie; a fine mese diventano medaglie nel profilo.
- **4 temi**, **home a modo tuo** e scheda iniziale in Impostazioni; **piede preferito** in Modifica profilo.

## Notifiche delle partite, link d'invito e pronostici (supabase/aggiornamento-notifiche.sql e funzione notify)
1. **Database** (una volta sola, dopo `aggiornamento-chat.sql`): Supabase → **SQL Editor** → **New query**, incolla tutto `supabase/aggiornamento-notifiche.sql` e premi **Run**. Deve comparire "Aggiornamento notifiche completato" con `promemoria_attivi` = 1. Non sposta e non cancella dati; si può rieseguire. Accende anche l'orologio del database (pg_cron) che ogni 10 minuti controlla i promemoria.
2. **Funzione notify** (va ripubblicata): Supabase → **Edge Functions** → `notify` → **Code** (o "Edit"), cancella il codice, incolla tutto il nuovo `supabase/functions/notify/index.ts` e premi **Deploy**. "Verify JWT" resta spento.
3. **Sito**: carica su GitHub `index.html` e `sw.js` (nella cartella principale), più questo file e i due di `supabase` nelle loro cartelle.

Cosa fa:
- **Notifiche delle partite**: nuova partita o sondaggio, "si gioca" quando il sondaggio sceglie il giorno, invito di un amico, posto libero per chi era in lista d'attesa, partita cambiata o annullata, voto MVP aperto, promemoria 24 ore prima. Ognuno le spegne in Impostazioni → Notifiche (restano quelle dei messaggi). Toccando la notifica si apre la partita.
- **Link e QR d'invito**: dal gruppo (Invita) e dalla partita (Link e QR). Con il link di un amministratore del gruppo si entra subito; con quello di un altro membro si chiede di entrare. "Rifai il link" cambia il codice: i link vecchi fanno solo chiedere di entrare. Chi non è iscritto si iscrive e poi arriva lì.
- **Pronostici**: a squadre fatte, nei Dettagli della partita, fino all'inizio. Quelli degli altri si vedono a partita iniziata (li mostra il database, non si possono sbirciare). Classifica nello Storico → Classifiche → Pronostici: 3 punti il risultato esatto, 1 l'esito.

Finché lo script non è eseguito, l'app funziona come prima: le parti nuove semplicemente non compaiono.

## Valutazioni, riepilogo di fine partita e Confronto (supabase/aggiornamento-valutazioni.sql)
1. **Database** (una volta sola): Supabase → **SQL Editor** → **New query**, incolla tutto `supabase/aggiornamento-valutazioni.sql` e premi **Run**. Deve comparire "Aggiornamento valutazioni completato". Non sposta e non cancella dati; si può rieseguire.
2. **Sito**: carica su GitHub `index.html` e `sw.js` (nella cartella principale), più questo file e lo script nella cartella `supabase`.

Cosa cambia:
- **Media sulle ultime 30**: ogni voce è la media delle ultime 30 valutazioni ricevute; l'autovalutazione conta come la più vecchia, quindi esce per prima. Ogni salvataggio è una valutazione in più (le precedenti restano nel documento di chi vota, campo `h`), ma lo stesso giocatore si può valutare al massimo 3 volte in 7 giorni. Le stats generali fanno lo stesso con le valutazioni di tutti i gruppi.
- **Riepilogo di fine partita** ("Com'è andata?"): a chi ha giocato si apre da solo una volta (e un'altra quando la partita viene chiusa), entro 4 giorni: risultato e marcatori, voto MVP, giocatori da valutare, invito al Confronto. Finché non si preme "Fatto" resta tra le cose da fare.
- **Confronto**: due compagni di gruppo e una voce, senza punteggi. Chi sceglie il più debole gli dà +2 e toglie 2 all'altro; il più forte non cambia niente; "Uguali" li avvicina di 1. Anonimo (tabella `cmp_votes`, si legge solo con le funzioni). La stessa coppia sulla stessa voce una volta al mese a persona, al massimo 150 confronti al giorno; in tutto una voce si sposta al massimo di 10 punti e i confronti invecchiano come le valutazioni. In home, nella scheda Giocatori e in fondo al riepilogo.
- **Traguardi di chi valuta**: 10, 50, 200 valutazioni date e 50, 250, 1000 confronti (in tutto 32 traguardi).

Finché lo script non è eseguito: il Confronto non compare, le valutazioni si sommano lo stesso (le stats generali usano solo le ultime di ogni gruppo) e i traguardi di chi valuta nella vista "Generali" restano a zero.

## Il Campo: squadre trascinando, panchina e formazioni (supabase/aggiornamento-panchina.sql)
1. **Database** (una volta sola, dopo `aggiornamento-notifiche.sql`): Supabase → **SQL Editor** → **New query**, incolla tutto `supabase/aggiornamento-panchina.sql` e premi **Run**. Aggiorna solo la funzione `match_push` (le notifiche delle partite); non sposta dati e si può rieseguire. Sul database del gruppo è già stato eseguito il 5 novembre 2026.
2. **Sito**: carica su GitHub `index.html` (nella cartella principale), più questo file e lo script nella cartella `supabase`.

Cosa cambia:
- **Il Campo è dove si fanno le squadre** (prima della chiusura): tenendo premuto un giocatore e trascinandolo su un altro si scambiano posto, ruolo e, se serve, squadra; su un posto libero il giocatore si sposta lì. Pressione lunga senza trascinare: il giocatore resta selezionato e poi si tocca dove va. Dopo ogni modifica, "Annulla" per qualche secondo. La scheda Squadre resta per il confronto; la vecchia modifica a elenco non c'è più.
- **Formazioni**: toccando il modulo di una squadra (o con "Formazioni") si sceglie tra i moduli del formato; l'app mette ognuno nel ruolo in cui rende di più. Il modulo scelto sta nella partita, in `teams.mods`.
- **Panchina**: linguetta sul bordo destro del campo con la lista d'attesa e chi non è ancora in squadra. Chi organizza (chi ha creato la partita, gli amministratori del gruppo e dell'app) fa entrare uno della lista d'attesa al posto di chi è in campo, dopo una conferma: i due si scambiano anche l'orario della risposta, quindi chi esce prende il numero in lista d'attesa di chi entra. Con le squadre scelte dai giocatori l'ordine sul campo sta in `teams.order`.
- **Notifiche**: chi entra riceve "Si è liberato un posto: giochi tu"; con lo script chi esce riceve "X ti ha messo in panchina per …: sei n° N in lista d'attesa". Dopo l'inizio della partita entrate e uscite non mandano più notifiche (sono correzioni).

Finché lo script non è eseguito: tutto funziona, ma chi va in panchina non riceve la notifica.

Stili del campo (solo app, nessuno script): il tastino in alto a sinistra sul Campo (e Impostazioni → Aspetto) apre la scelta tra erba a strisce, erba a scacchi, sintetico, campetto in terra, spiaggia, neve, sull'acqua, Marte, palazzetto, lavagna, calcio balilla e sotto i riflettori. Vale per quel telefono (`sc-campo`); con "Riduci movimento" neve e onde stanno ferme. Anche la locandina da condividere usa lo stile scelto (lo stesso disegno dello schermo; se il telefono non riesce a disegnarlo, usa il prato a strisce). Il risultato da condividere non ha il campo.

## Valore in campo: conta il ruolo (solo `index.html`, nessuno script)
Carica su GitHub `index.html` (nella cartella principale) e questo file.

Cosa cambia:
- **Valore di un giocatore in campo**: l'area del reparto in cui gioca conta il doppio. Un attaccante vale (2 × Attacco + Centrocampo + Difesa + Generale) / 5, un difensore raddoppia la Difesa, un centrocampista il Centrocampo; in porta conta la Porta. Restano il malus fuori ruolo (3 punti in un ruolo vicino, 6 in uno lontano, rispetto al ruolo e al secondo ruolo) e quello degli infortuni. Il peso del reparto è `CFG.REPARTO` nel motore (2).
- **Confronto**: le righe Attacco, Centrocampo e Difesa sono la media di chi gioca fuori dai pali, con chi gioca in quel reparto che conta il doppio; il Generale resta una media semplice. Spostare un attaccante in difesa ora cambia le righe, il valore medio e l'equilibrio.
- **Il punteggio della card non cambia** (media delle quattro aree, o la Porta per i portieri): colori, classifiche e storico restano uguali.
- **Squadre automatiche**: usano lo stesso calcolo, quindi mettono ognuno dove rende di più. La ricerca rifà con il calcolo vero fino a 480 divisioni (prima 120): fino a 12 giocatori le prova tutte, a 7 e a 8 trova la migliore molto più spesso. Chi rende di più nel secondo ruolo non conta come "fuori ruolo".
- **Squadre già fatte**: non cambiano da sole; si rifanno quando cambia chi gioca, o con "Crea squadre" e "Mischia" nel Campo. I numeri del Confronto invece si aggiornano subito, anche per le partite già giocate ("Calcolato con le stats di oggi"); la previsione salvata alla chiusura resta quella di allora.

## Disegni più dettagliati (solo `index.html`, nessuno script)
Carica su GitHub `index.html` (nella cartella principale) e questo file.

- **Maglie**: maniche e colletto nel colore del bordino (scuro sulle maglie chiare, bianco sulle altre; si può fissare per un colore con `trim` in `TEAM_COLORS`), polsini nel colore della squadra, righe tono su tono, pieghe, luce da sinistra in alto e ombra sul prato. Uguali sul campo, nel giocatore che si trascina, nelle etichette delle squadre, nella scelta dei colori, nella locandina e nel risultato da condividere.
- **Campo**: una grana per ogni stile (fili d'erba, granuli di gomma, terra e sassolini, sabbia, neve che luccica, riflessi sull'acqua, polvere di Marte, venature del parquet, polvere di gesso, panno del calcio balilla); zone consumate davanti alle porte, sul dischetto e a centrocampo sull'erba; porte con la rete in profondità, pali e ombra della traversa; luce da sinistra in alto (non sotto i riflettori e nel palazzetto, che hanno le loro luci). Le grane sono piastrelle di 128×128 disegnate dal telefono la prima volta che servono (pochi millesimi di secondo l'una): niente immagini da scaricare.
- **Card**: bordo smussato, linee e fregi in rilievo, punteggio, nome e numeri coniati, finestra della foto incassata; uguale nella card da condividere.
- La locandina usa lo stesso campo dello schermo anche con l'erba a strisce (prima solo con gli altri stili); se il telefono non ci riesce, resta il prato a strisce semplice.

## Versione, aggiornamenti e indirizzo unico (`index.html` e `sw.js`, nessuno script)
Carica su GitHub `index.html`, `sw.js`, `.gitignore`, `.vercelignore` (le prove non vanno online), le cartelle `prove` e `.github` e questo file.

- **Apertura veloce**: il service worker (`sw.js`, ora v19) apre l'app dalla copia salvata sul telefono, senza aspettare la rete; intanto chiede a Vercel se `index.html` è cambiato (una richiesta leggera: se non è cambiato risponde «uguale»). Icone, comuni, emoji e `config.js` arrivano anche loro dalla copia e si rinfrescano dietro le quinte. Senza rete l'app si apre lo stesso (i dati però arrivano solo con la rete). I caratteri (Bricolage e Geist) non fermano più l'apertura: finché non arrivano si usano quelli del telefono. La copertina iniziale resta un attimo invece di quasi un secondo e mezzo.
- **Aggiornamenti**: quando la versione nuova è sul telefono compare in alto **«Nuova versione pronta»** con **Aggiorna**, anche sulla schermata di accesso; con la × sparisce e la versione nuova parte alla prossima apertura. Prima l'app si ricaricava da sola quando cambiava il service worker: ora no, così nessuno perde quello che sta scrivendo.
- **Versione e Novità**: la versione è `APP_VER` in `index.html` (anno.mese.giorno, poi .2, .3… se escono più versioni nello stesso giorno) e si vede in fondo al menu, in Impostazioni → App e in Come funziona. **A ogni modifica dell'app va alzata e va aggiunta in cima a `NOVITA` una voce con le novità per chi gioca**: le prove controllano che la prima voce abbia la stessa versione. Le Novità sono nel menu; dopo un aggiornamento si aprono da sole una volta (non a chi si è appena iscritto e non nella demo). In Impostazioni → App c'è anche **Cerca aggiornamenti**.
- **Indirizzo unico**: l'app sta solo su **algor-bomber.vercel.app**. Gli altri due progetti Vercel (`algor-bomber-4aox` e `algor-bomber-67f5`) pubblicano lo stesso codice, che lì fa una cosa sola: nel browser porta subito a algor-bomber.vercel.app (con il link della partita o del gruppo, se c'è, e le preferenze del telefono: tema, colore, home, stile del campo, emoji recenti e gruppo scelto); nell'app installata da un indirizzo vecchio mostra «L'app ha cambiato indirizzo» con i passi (apri il nuovo indirizzo, accedi con la solita email e password, metti l'app nella schermata Home, attiva le notifiche, cancella l'icona vecchia) e un «Per ora continua qui». Toccando «Apri il nuovo indirizzo», e sempre nel browser, le notifiche dell'indirizzo vecchio si spengono, se no arriverebbero doppie. I link d'invito e quelli delle email (password, conferma dell'iscrizione) usano sempre algor-bomber.vercel.app. Sull'indirizzo nuovo bisogna rifare l'accesso: ogni indirizzo tiene il suo.
- **Dopo la pubblicazione**: su Vercel, nei progetti `algor-bomber-4aox` e `algor-bomber-67f5`, **Settings → Git → Disconnect**, così restano fermi a questa versione (quella che porta al nuovo indirizzo) e non pubblicano più niente. In Supabase → **Authentication → URL Configuration**: **Site URL** `https://algor-bomber.vercel.app` e la stessa in **Redirect URLs**.

## Prove automatiche (cartella `prove` e `.github/workflows/prove.yml`)
A ogni pull request GitHub prova l'app da solo, in qualche minuto, e mette il risultato (✓ o ✗) nella pull request; le foto fatte durante le prove si scaricano dalla pagina della prova (**Actions** → la prova → **Artifacts**). Cosa prova:
- `prova_giro.py`: tutte le partite e tutte le schede si aprono senza errori, con i dati di esempio.
- `prova_campo.py` e `prova_campo_altro.py`: il Campo col dito (trascinare, tenere premuto, panchina, formazioni, scorrimento, tastiera, mouse).
- `prova_stili.py` e `prova_locandina.py`: gli stili del campo, sullo schermo e nella locandina.
- `prova_valore.py`: il valore in campo per reparto e la ricerca delle squadre.
- `prova_presenze.py`: ritoccare «Ci sono» su un compagno già iscritto non lo manda in fondo alla lista (prima succedeva).
- `prova_versione.py`, `prova_aggiorna.py`, `prova_indirizzo.py`: versione e Novità, apertura dalla copia, «Aggiorna», senza rete, passaggio dal service worker di prima, indirizzi vecchi.
- `sql/prova_panchina.mjs` e `sql/prova_regole.mjs`: gli script del database della panchina e delle regole, su un Postgres in memoria.

Per lanciarle sul computer: `pip install playwright pillow`, Chrome installato, `npm ci` dentro `prove/sql`, poi `python3 prove/esegui.py` (o solo alcune: `python3 prove/esegui.py campo`). Una prova che non passa al primo colpo viene ripetuta una volta e lo dice nel riepilogo.

## Regole delle partite nel database (supabase/aggiornamento-regole.sql)
Finora i permessi sulle partite li controllava solo l'app: chi avesse scritto nel database "a mano", con il proprio accesso, poteva fare anche quello che l'app non lascia fare (segnarsi «pagato», passare davanti in lista d'attesa, cambiare il risultato di una partita vecchia…). Con questo script le stesse regole le controlla anche il database. Per chi usa l'app non cambia niente: le regole sono quelle che l'app già rispetta.

- **Una volta sola**: Supabase → **SQL Editor** → **New query**, incolla tutto `supabase/aggiornamento-regole.sql` e premi **Run**. Deve comparire "Aggiornamento regole completato" con `regole_attive` = 1. Non sposta e non cancella dati; si può rieseguire.
- **Cosa controlla** (chi organizza = chi ha creato la partita, gli amministratori del gruppo e dell'app):
  - chi ha creato la partita non si cambia; una partita nuova si crea a nome proprio, aperta o come sondaggio, con dentro al massimo sé stessi;
  - colori delle squadre e sondaggio (annullarlo, giorni, voti): chi organizza; i voti passano sempre dalla funzione del sondaggio;
  - iscritti e ospiti: chiunque nel gruppo li segna, come nell'app; spostare gli altri da una squadra all'altra lo fa chi organizza; un ospite si aggiunge a nome proprio e resta di chi l'ha portato;
  - orari d'iscrizione veri: uno "nel passato" (per passare davanti in lista) diventa l'ora di adesso;
  - campo prenotato: a nome proprio; lo toglie chi l'ha segnato o chi organizza;
  - cassa: prezzo e quota li scrive chi organizza, chi ha prenotato o chi raccoglie; «pagato» lo segna chi raccoglie o un amministratore del gruppo;
  - risultato, marcatori e chiusura: dopo l'inizio della partita successiva solo gli amministratori del gruppo e dell'app (come nell'app);
  - inviti: a nome proprio.
- **Chi non è toccato**: gli amministratori dell'app e le funzioni del database (sondaggio, notifiche, promemoria), che scrivono per conto di chi le usa.
- Se qualcuno prova a fare altro riceve un messaggio in italiano (per esempio «I colori delle squadre li cambia chi organizza la partita.»), che l'app mostra così com'è.
- Da sapere: oggi nell'app **chiunque nel gruppo** cambia giorno, ora e campo, annulla una partita e segna la presenza degli altri. Il database fa lo stesso. Se un giorno queste cose devono farle solo gli organizzatori, vanno cambiate insieme l'app e questo script.

## Cose da sapere
- Chiunque abbia il link può iscriversi. Se vuoi limitare l'accesso, in Supabase puoi disattivare le nuove iscrizioni (Authentication → Sign In / Providers → "Allow new users to sign up") dopo che sono entrati tutti.
- I progetti gratuiti di Supabase vengono messi in pausa dopo qualche giorno senza uso: se succede, dal sito di Supabase si riattiva con un clic. Verifica le condizioni attuali del piano gratuito.
- Se qualcuno si iscrive due volte con email diverse, un amministratore dell'app elimina l'account doppio dall'app: menu ☰ → **Amministrazione** → **Account**.
- I numeri di telefono dei campi arrivano da Google Maps: controlla orari e prezzi chiamando.
