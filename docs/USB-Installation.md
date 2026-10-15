# Installazione da chiavetta USB

Versione USB: **2.10.12**. Non richiede Intune, Azure, certificati o rete.

I file pronti sono in `package\usb\output\DO-Monitor-Local-USB-2.10.12`.
Copiare **tutti i file** della cartella sulla chiavetta, poi avviare
**`Installa.cmd`** con doppio clic e autorizzare UAC. Nessuno ZIP da estrarre.
Attendere codice risultato **0**, quindi si puo' rimuovere la chiavetta.

Lo script viene installato in `%ProgramFiles%\DO-Monitor-Local`; il task
`DO-Monitor Local Collector` gira come **SYSTEM ogni 5 minuti** e non dipende
dalla presenza della chiavetta. Viene richiesta anche una prima esecuzione.
Gli snapshot vengono salvati sul disco del PC in
`%ProgramData%\DO-Monitor-Local\DO-*.json`, non sulla chiavetta.
Sono necessari Windows 10/11 a 64 bit e credenziali amministrative per UAC.
Il task puo' eseguire solo quando il PC e' acceso; nessun riavvio e' richiesto.

Per rimuovere il collector, avviare **`Disinstalla.cmd`** e autorizzare UAC:
**gli snapshot sono conservati**. Per reinstallare, ripetere `Installa.cmd`.
Installazione e raccolta riutilizzano gli stessi componenti della variante
locale Win32; non contengono strumenti Intune o contenuti del pacchetto Azure.
La variante USB usa la propria versione di installazione.
Come richiesto, la variante USB non verifica il checksum del collector;
restano i controlli su versione, task e permessi. La variante Intune e' invariata.

Il task/cartella sono gli stessi della variante locale Intune: non usare
contemporaneamente un'assegnazione Intune Required, che potrebbe ripristinare
la propria versione. Il task Azure separato rimane invariato.

I dati non vengono caricati o cancellati automaticamente. Prevedere raccolta
e pulizia; vedere [analizzatore offline](Local-Snapshot-Analysis.md).
Cartelle preesistenti non compatibili vengono rifiutate, senza cancellare dati.
I criteri di esecuzione imposti dall'organizzazione restano applicabili.

Per preparare una nuova cartella, dopo aver incrementato `VERSION`:

```powershell
.\package\Build-USBPackage.ps1
```

Il builder riutilizza i sorgenti locali, imposta la versione senza checksum e
include solo i file necessari. Le versioni esistenti non vengono sovrascritte.
