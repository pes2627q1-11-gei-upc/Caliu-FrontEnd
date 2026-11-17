# Selector de radi de cerca (#110, HU #4)

La cerca permet escollir entre 0,1 i 500 km i aplicar el radi des de la
posició real de l'usuari. El valor inicial del control és 15 km, però no
s'aplica cap radi fins que es prem «Aplicar radi» i s'obté la ubicació.
No requereix iniciar sessió.

El radi i el centre es comparteixen entre Inici i Mapa. Desplaçar el mapa
no canvia el centre del filtre. «Treure radi» recupera la cerca sense radi
i la càrrega del mapa segons la zona visible. La cerca conserva text,
categories, municipi, comarca i dates en aplicar o treure el radi.

Durant la localització es desactiva l'aplicació del radi. En cas d'error,
permís denegat o timeout, no s'envien coordenades substitutives ni radi.
El missatge provisional és: «No podem aplicar el radi sense la teva
ubicació. Activa-la i torna-ho a provar.» Cal validar-lo amb l'equip.

## Contracte i coordinació

- `GET /events`: `lat`, `lng`, `radiusKm`, juntament amb els altres filtres.
- Límits actuals: 0,1–500 km. La revisió de validació del servidor i els
  seus tests corresponen a #111; si canvien, ajustar `SearchRadius`.
- No es desen preferències. #124/#125 poden aportar el valor inicial del
  control i aplicar-lo a través de l'estat compartit, sense crear un altre
  selector a la cerca.

## Prova manual pendent (web)

1. Arrencar amb `powershell.exe -NoProfile -File .\scripts\run-web.ps1`.
   Cal la configuració de Maps descrita al README i un navegador amb
   geolocalització disponible a localhost o HTTPS.
2. Sense sessió, cercar un text, triar categories i dates, escollir un radi
   i prémer «Aplicar radi». Acceptar el permís d'ubicació.
3. A Network, comprovar que `/events` envia la ubicació rebuda,
   `radiusKm` i els altres filtres. Verificar els extrems 0,1 i 500 km.
4. Obrir Mapa i desplaçar-lo: les peticions han de mantenir el centre i el
   radi aplicats. Comprovar que els marcadors són dins d'aquesta distància.
5. Tornar a Inici i treure el radi: es conserven els altres filtres i no
   s'envien els paràmetres geogràfics de la cerca.
6. Denegar ubicació i repetir; simular també timeout i serveis desactivats.
   Ha d'aparèixer el missatge, sense aplicar el radi. Restablir el permís
   i reintentar. Cancel·lar durant la localització no ha de reaplicar-lo.

Els tests automàtics usen ubicacions i HTTP simulats. No acrediten que el
GPS del navegador ni el servei desplegat funcionin en un dispositiu real.
