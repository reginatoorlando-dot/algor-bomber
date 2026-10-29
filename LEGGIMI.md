# Algor Bomber — guida per metterla online

Servono tre account gratuiti: **GitHub**, **Supabase**, **Vercel**. Tempo: circa 20 minuti.
Il sito è la cartella `web` (questa). Il resto dello zip (`sorgenti`) serve solo per le modifiche future.

## 1. Il database (Supabase)
1. Vai su supabase.com → **New project**. Scegli un nome (es. `algor-bomber`), una password per il database (salvala) e una regione europea.
2. Quando il progetto è pronto apri **SQL Editor** → **New query**, incolla tutto il contenuto di `supabase/schema.sql` e premi **Run**. Deve comparire "Success". Poi, in una nuova query, fai lo stesso con `supabase/aggiornamento-gruppi.sql` (gruppi, chat, amministrazione).
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

## Cose da sapere
- Chiunque abbia il link può iscriversi. Se vuoi limitare l'accesso, in Supabase puoi disattivare le nuove iscrizioni (Authentication → Sign In / Providers → "Allow new users to sign up") dopo che sono entrati tutti.
- I progetti gratuiti di Supabase vengono messi in pausa dopo qualche giorno senza uso: se succede, dal sito di Supabase si riattiva con un clic. Verifica le condizioni attuali del piano gratuito.
- Se qualcuno si iscrive due volte con email diverse, un amministratore dell'app elimina l'account doppio dall'app: menu ☰ → **Amministrazione** → **Account**.
- I numeri di telefono dei campi arrivano da Google Maps: controlla orari e prezzi chiamando.
