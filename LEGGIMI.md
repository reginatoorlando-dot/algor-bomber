# Algor Bomber — guida per metterla online

Servono tre account gratuiti: **GitHub**, **Supabase**, **Vercel**. Tempo: circa 20 minuti.
Il sito è la cartella `web` (questa). Il resto dello zip (`sorgenti`) serve solo per le modifiche future.

## 1. Il database (Supabase)
1. Vai su supabase.com → **New project**. Scegli un nome (es. `algor-bomber`), una password per il database (salvala) e una regione europea.
2. Quando il progetto è pronto apri **SQL Editor** → **New query**, incolla tutto il contenuto di `supabase/schema.sql` e premi **Run**. Deve comparire "Success". Poi, ognuno in una nuova query e in quest'ordine, fai lo stesso con `supabase/aggiornamento-gruppi.sql` (gruppi, chat, amministrazione) con `supabase/aggiornamento-iscritti.sql` (iscritti visibili a tutti, stats generali, aggiunta ai gruppi) con `supabase/aggiornamento-partite.sql` (comune dei gruppi, modifica del gruppo, sondaggio sul giorno) con `supabase/aggiornamento-amici.sql` (amicizie) con `supabase/aggiornamento-traguardi.sql` (traguardi di tutti) e con `supabase/aggiornamento-chat.sql` (chat come WhatsApp; per le notifiche serve anche la funzione `notify`, vedi più sotto).
3. **Authentication → Providers → Email**: lascia attivo l'accesso con email e **disattiva "Confirm email"** (così gli amici entrano subito senza aspettare la mail).
4. **Project Settings → API**: copia **Project URL** e la chiave **anon public**.
5. Apri il file `config.js` di questa cartella e incolla i due valori al posto delle scritte `INCOLLA_QUI_…`. (La chiave anon può stare nel sito: la sicurezza la fanno le regole del database.)

## 2. Il codice (GitHub)
1. Su github.com crea un repository nuovo (es. `algor-bomber`), privato va bene.
2. **Add file → Upload files** e trascina **il contenuto della cartella `web`** (index.html, config.js, sw.js, manifest, icone, cartella supabase). Premi **Commit**.

## 3. Il sito (Vercel)
1. Su vercel.com accedi con GitHub → **Add New → Project** → scegli il repository `algor-bomber` → **Deploy** (nessuna impostazione da cambiare: è un sito statico).
2. Al termine ottieni un indirizzo tipo `calcetto-xxxx.vercel.app`. È il link da mandare agli amici.
3. Torna su Supabase → **Authentication → URL Configuration** e incolla quell'indirizzo in **Site URL** (serve al link "password dimenticata").

## 4. Installarla sul telefono
- **Android (Chrome):** apri il link → menu ⋮ → **Installa app** (o "Aggiungi a schermata Home").
- **iPhone (Safari):** apri il link → Condividi → **Aggiungi a schermata Home**.
Ha la sua icona e si apre a schermo intero.

## Aggiornare l'app per tutti
Quando ti mando una versione nuova, sostituisci i file su GitHub (**Add file → Upload files**, stessi nomi, **Commit**). Vercel pubblica da solo in un minuto; gli amici la ricevono alla prossima apertura (a volte serve chiuderla e riaprirla una volta). I dati nel database restano.
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
Chiunque vede i traguardi di chiunque dal suo profilo. Nella vista "Nel gruppo" contano le partite del gruppo; nella vista "Generali", e per chi non è nel tuo gruppo, contano tutte le partite in tutti i gruppi. Per questi ultimi serve una funzione nuova del database: in Supabase apri **SQL Editor**, incolla tutto il contenuto di `supabase/aggiornamento-traguardi.sql` ed esegui (Run). Deve comparire "Aggiornamento traguardi completato". Non modifica né cancella dati: aggiunge solo una funzione di lettura, che restituisce i dati di quella persona senza dire chi sono i compagni né quali sono i gruppi. Finché non lo esegui, l'app mostra i traguardi del gruppo per i compagni e un avviso per gli altri.

## Chat come WhatsApp (supabase/aggiornamento-chat.sql e funzione notify)
La scheda Messaggi ha le chat dei gruppi e le chat private tra compagni di gruppo o amici (le leggono solo le due persone, nemmeno gli amministratori dell'app). Si mandano foto (ridotte sul telefono a circa 300 KB), GIF e sticker, emoji e vocali; si risponde a un messaggio, si reagisce, si inoltra in un'altra chat, si modifica nei primi 15 minuti, si elimina per tutti; ci sono le spunte, «sta scrivendo…», le menzioni con @ e le notifiche sul telefono. Niente video, per non riempire lo spazio gratuito (1 GB): gli amministratori dell'app vedono quanto spazio usano foto e vocali in Amministrazione.

1. **Database** (una volta sola): Supabase → **SQL Editor** → **New query**, incolla tutto `supabase/aggiornamento-chat.sql` e premi **Run**; deve comparire "Aggiornamento chat completato". Non sposta e non cancella dati; si può rieseguire. Finché non lo esegui, nella chat si scrive solo testo.
2. **Notifiche** (una volta sola): Supabase → **Edge Functions** → **Deploy a new function** → **Via Editor**. Nome: `notify`. Cancella l'esempio, incolla tutto `supabase/functions/notify/index.ts` e premi **Deploy**. Poi, nella pagina della funzione, apri **Settings** (o Details), spegni **Enforce JWT verification** / **Verify JWT** e salva: chi chiama lo controlla la funzione stessa. Non servono segreti: le chiavi delle notifiche le crea la funzione la prima volta e le tiene nel database.
3. Ognuno attiva le notifiche dal proprio telefono: scheda Messaggi (riquadro "Attiva le notifiche") o menu ☰ → Impostazioni → Notifiche, dove c'è anche "Manda una prova". Su iPhone funzionano solo con l'app aggiunta alla schermata Home (Safari → Condividi → Aggiungi alla schermata Home) e aperta da lì.
4. **GIF e sticker** (facoltativo): servono una chiave gratuita di KLIPY (partner.klipy.com → API Keys) da mettere in `config.js` alla voce `klipyKey`. Senza chiave si possono comunque mandare le GIF salvate nel telefono dalla Galleria.

## Cose da sapere
- Chiunque abbia il link può iscriversi. Se vuoi limitare l'accesso, in Supabase puoi disattivare le nuove iscrizioni (Authentication → Sign In / Providers → "Allow new users to sign up") dopo che sono entrati tutti.
- I progetti gratuiti di Supabase vengono messi in pausa dopo qualche giorno senza uso: se succede, dal sito di Supabase si riattiva con un clic. Verifica le condizioni attuali del piano gratuito.
- Se qualcuno si iscrive due volte con email diverse, un amministratore dell'app elimina l'account doppio dall'app: menu ☰ → **Amministrazione** → **Account**.
- I numeri di telefono dei campi arrivano da Google Maps: controlla orari e prezzi chiamando.
