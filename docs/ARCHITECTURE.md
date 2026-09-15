# opx77_admin — architecture

`opx77_admin` est le poste du staff : chaque action (téléporter, soigner, tuer, expulser, bannir,
faire apparaître un véhicule, donner une arme, toucher à un sac, annoncer) est une commande
restreinte de cette resource, et le menu dessiné par `opx77_menu` n'en est qu'un frontal. Elle ne
possède aucune donnée de personnage : ce qu'un personnage *est* appartient à `opx77_core`, ce qu'il
*porte* à `opx77_inventory`, l'heure et la météo à `opx77_weather` ; le menu pilote leurs propres
commandes ou leurs exports. Elle ne persiste rien en base. Le code est commenté en anglais, cette
documentation est en français ; le mode d'emploi (commandes, permissions, configuration, locales)
est dans le `README.md`.

## Manifeste

L'ordre de chargement est l'ordre du manifeste.

Scripts partagés : `config.lua` d'abord, puis `shared/text.lua` (les coercitions dont tout le reste
dépend), puis `shared/locale.lua`, qui applique `LOCALE` à son chargement
(`OpxAdmin.Locale.Set(OPX_ADMIN_CONFIG.LOCALE)` en fin de fichier, sinon `LOCALE` serait inerte),
et aussitôt les deux catalogues `locales/en.lua` et `locales/fr.lua`, pour qu'aucun fichier plus
bas n'appelle `locale()` contre un catalogue vide. Viennent ensuite les deux fichiers de données
`data/vehicles.lua` et `data/weapons.lua`, avant l'index `shared/catalog.lua` qui les lit, puis
les parties `shared/catalog-1.lua` à `shared/catalog-4.lua`, dans cet ordre, la dernière en
dernier (voir « Indexer le catalogue par parties »).

Côté serveur, `server/main.lua` charge en premier : il crée `OpxAdmin.Server` et le registre
`OpxAdmin.Server.Command` par lequel tous les autres fichiers enregistrent leurs commandes.
`server/inventory.lua` passe avant `server/weapons.lua` et `server/menu.lua`, qui appellent le
pont `OpxAdmin.Inventory`. `server/menu.lua` passe en dernier : la carte d'accès qu'il envoie
liste ce que tous les autres fichiers ont enregistré.

Côté client, `client/main.lua` d'abord (appel d'exports, canal de commande, déplacements), puis
`client/keys.lua` avant `client/controls.lua` et `client/menu.lua`, qui enregistrent leurs touches
à travers `OpxAdmin.Keys` ; `client/forms.lua` avant `client/menu.lua`, car une ligne du menu peut
ouvrir un formulaire ; `client/exports.lua` en dernier, car publier la surface affirme qu'elle
existe.

`reload_policy "local"` : la resource n'a pas de surface CEF à elle ; `opx77_menu` et
`opx77_input` dessinent tout, et tous deux retirent le menu et le formulaire de cette resource
quand sa génération change. Un rechargement reconstruit donc les deux moitiés sans reconnexion ;
les destinations ajoutées en jeu survivent à un rechargement, pas à un redémarrage.

Aucune `dependency` n'est déclarée. Une dépendance déclarée est dure, et un outil de staff qui
refuse de démarrer parce qu'`opx77_menu` manque n'est plus un outil au moment où il faut expulser
quelqu'un : chaque commande fonctionne encore depuis le chat et la console sans le menu.

- `network.events` — les deux moitiés : les envois de listes et de déplacements vers le client,
  la demande de rafraîchissement vers le serveur, les lignes de commande du menu envoyées par
  `open77:command:execute`. C'est aussi la seule permission dont le holster a besoin :
  `Open77.weapons` côté serveur est un relais sur des événements réseau. Les autres commandes
  d'arme et d'inventaire appellent les exports serveur d'`opx77_inventory`, qui ne demandent
  aucune permission ici.
- `acl.read` — serveur : `Open77.acl.isAllowed`, pour revérifier l'événement de rafraîchissement
  et les modes de déplacement contre les mêmes `command.<name>` que l'hôte résout, et filtrer les
  suggestions du chat. Lecture seule : la resource n'écrit jamais un rôle ni une permission.
- `players.life.read` — l'état de vie et la porte de disponibilité, avant de faire quoi que ce
  soit à qui que ce soit.
- `players.life.kill` — `opx77.admin.player.kill`, et la première moitié de chaque placement.
- `players.life.respawn` — un placement est kill puis respawn, jamais une écriture de transform.
- `players.life.revive` — la réanimation, et la reprise quand le respawn d'un placement est
  refusé.
- `players.damage.read`, `players.damage.apply`, `players.stats.read`, `players.stats.apply` —
  `getHealth`, `setHealth`, `setArmor`, `setGodMode` ; quelle famille garde quelle liaison n'est
  pas documenté, et le paquet d'administration officiel déclare les deux, donc celle-ci aussi.
- `players.disconnect` — `Open77.players.kick`.
- `players.access` — `Open77.access.ban` : la liste de bannissements locale au serveur, jamais
  l'ACL.
- `world.vehicles` — créer, réparer, marquer et retirer les véhicules que cette resource crée.
- `player.travel` — client : `Open77.travel.setNoclip`, `setNoclipSpeed`, `setMapPick`,
  appliqués seulement quand une commande serveur gardée par l'ACL le dit.
- `clipboard.write` — client : `opx77.admin.self.pos` copie une ligne `LOCATIONS` à coller dans
  la configuration.
- `input.actions` — client : `RegisterKeyMapping` pour la touche du menu et les deux touches de
  vitesse, `Open77.input.keyFor` pour la touche que nomme la ligne Fermer, et `isCaptured`, pour
  qu'une touche tapée dans le chat ou un formulaire ne fasse rien. Chaque touche envoie la même
  ligne de commande que le chat ; aucune n'autorise quoi que ce soit.

Volontairement non demandées : `database.access` (rien ne persiste en base), `world.props`,
`world.effects`, `vehicles.performance`, `local.events`.

## Contrats

- **Les commandes** : toutes restreintes, toutes sous `opx77.admin` (liste dans le README). Leurs
  noms sont les chaînes ACL `command.<name>` des opérateurs ; ils ne changent pas.
- **Les exports client** `open`, `close`, `state` répondent une table portant `ok` et ne lèvent
  jamais. L'appelant est lu de l'hôte (`GetInvokingResource`), jamais d'un argument. `open` envoie
  la commande ouvreuse, que l'hôte résout contre l'ACL du joueur : `ok = true` veut dire
  « demandé », pas « autorisé » ; un joueur refusé reçoit le refus de l'hôte, qu'`opx77_chat`
  toaste, et pas de menu.
- **Les événements `opx77_admin:*`** sont privés à la resource (README, « Exports and events ») :
  des listes et des réponses du serveur vers le client, et un seul événement entrant,
  `opx77_admin:refresh`, qui ne fait que redemander une liste. Aucune mutation n'arrive par un
  événement : un événement réseau ne porte aucune autorisation sur cette plateforme, et en ajouter
  un serait un trou.
- **Les codes de refus** (`AdminError` dans `std/types.lua`) restent des codes dans l'audit et le
  journal ; un joueur lit la clé `admin.error.*` que `ERRORS` (`server/main.lua`) leur associe.
- **Les commandes des autres resources** que le menu pilote sont nommées par `LINKS`
  (`opx77.where`, `opx77.job`, `opx77.gang`, `opx77.money`, `opx77`, `opx77.save`,
  `opx77.inventory.open`, `opx77.inventory.holders`, `opx77.weather.*`) ; un renommage chez elles
  se suit dans `config.lua`, `false` retire la ligne.
- **`opx77_inventory`** liste `opx77_admin` dans son `EXPORTS.WRITERS` ; cette resource appelle ses
  exports serveur `GetItems`, `GetInventory`, `CanCarry`, `AddItem`, `RemoveItem`,
  `ClearInventory`, `GetHeldWeapon`. Côté client elle appelle `opx77_menu` (`open`, `update`,
  `setStatus`, `close`), `opx77_input` (`open`, `close`), `opx77_notify` (`show`),
  `opx77_prompts` (`show`, `hide`) et `opx77_core` (`GetJobs`, `GetGangs`, `GetSharedConfig`).

## L'ACL de l'hôte est la seule autorité

Chaque commande passe par `OpxAdmin.Server.Command`, qui appelle `RegisterCommand(name, handler,
true)` : l'hôte résout `command.<name>` contre `acl.jsonc` avant que le handler ne tourne. Aucun
handler ne vérifie de permission, et aucun ne doit le faire : l'hôte a déjà tranché, et une
seconde vérification ne ferait que diverger de la sienne. `Server.Command` n'a pas d'argument pour
une commande non restreinte : chaque commande agit sur le monde ou sur quelqu'un.

`OpxAdmin.Server.Permitted` interroge `Open77.acl.isAllowed` avec la même chaîne, mais seulement
là où il n'y a pas de commande : l'événement de rafraîchissement du menu, le balayage de
révocation des modes de déplacement, les suggestions du chat. Il répond `nil` quand l'hôte n'a pas
de lecteur d'ACL ou qu'il lève, ce que les appelants lisent comme « impossible à dire » ; la
console est toujours autorisée. Sans `Open77.acl`, un avertissement au boot le dit : le menu ne
grise plus, les modes de déplacement ne sont plus révoqués, mais chaque commande reste gardée.

`config.lua` est un script partagé, que chaque client télécharge : il ne contient ni secret ni
autorisation. La carte d'accès envoyée au menu ne sert qu'à griser ce que l'hôte refuserait.

Suggestions : sur `chat:ready`, elles ne partent que pour les commandes que l'ACL laisserait
lancer au joueur, pour que la liste des commandes staff ne soit pas remise à quiconque ouvre le
chat ; le plancher `cooled` (2 s) borne l'événement.

## Registre, cadence et départs

`OpxAdmin.Server.Command` garde les commandes dans l'ordre d'enregistrement (suggestions, carte
d'accès, ligne de boot) et refuse un doublon par un log. Chaque exécution passe par `cooled` : un
plancher par opérateur et par commande, `RATE.READ_MS` pour une commande de lecture,
`RATE.ACTION_MS` sinon ; la console n'est jamais refroidie. Le handler tourne sous `pcall` : une
levée dans un handler de commande serait sinon avalée sans réponse ; elle est journalisée et
répondue `failed`. Une commande `inGame` est refusée à la console. Le même plancher,
`OpxAdmin.Server.Cooled`, sert à `chat:ready` et à chaque sujet de rafraîchissement du menu
(créneau `refresh:<topic>`) : une seule table, `lastRun`, et un seul handler de départ l'oublie.

`OpxAdmin.Server.Count` lit `args.n`, qui fait foi : `#args` s'arrête au premier trou.
`OpxAdmin.Server.NowMs` (et `OpxAdmin.Client.NowMs`) convertit `Open77.time.monotonic`, qui répond
en secondes ; une lecture non finie n'est jamais prise, car un NaN n'expirerait rien et un infini
tout. Côté serveur, une lecture échouée passe à `GetGameTimer` (monotone sur le processus, serveur
seulement ; journalisé une fois), comme `opx77_chat`, `opx77_status` et `opx77_weather` : une
horloge figée gèlerait `OpxAdmin.Server.Cooled` (une commande ne repasserait plus pour le même
opérateur), le cache du catalogue et le balayage des armes en attente. Si les deux échouent, la dernière lecture est gardée. Le client n'a pas de
repli : `GetGameTimer` n'existe pas côté client. `OpxAdmin.Server.Setting` rend le nombre configuré ou le repli pour tout ce sur
quoi l'arithmétique lèverait.

`onPlayerDisconnected` est le seul événement de départ que lève la plateforme ; chaque fichier qui
tient un état par joueur ajoute son propre handler (`server/main.lua` pour tous les planchers,
`server/players.lua` pour les modes de déplacement et la vitesse choisie) : un id recyclé ne doit pas hériter des
interrupteurs du dernier occupant.

Au chargement de `server/main.lua`, les problèmes du catalogue (`OpxAdmin.Catalog.problems`) sont
journalisés, une clé présente dans un catalogue de locale et absente de l'autre est nommée (c'est
un défaut, pas un repli), et l'absence de `Open77.acl` est signalée.

## Réponses

`OpxAdmin.Server.Answer` répond à celui qui a lancé la commande. Un joueur la lit dans le catalogue
configuré, envoyée à la moitié client par `opx77_admin:answer` : un rapport (clé
`admin.text.lines`, `REPORT`) devient une ligne de chat, qu'on relit et compare et qu'un toast
couperait ; le résultat d'une action devient un toast. Jamais sur `open77:command:result`, dont
`opx77_chat` n'imprime pas les réponses acceptées. Sans genre donné, il est déduit : succès si
`ok`, avertissement pour une clé `admin.usage.*`, erreur sinon. La console lit l'anglais
(`OpxAdmin.Locale.English`), parce que cette réponse finit dans un journal qu'un opérateur
parcourt avec grep.

`OpxAdmin.Server.Refuse` répond un refus par son code. `params.reason` est le mot de l'hôte quand
il en a donné un (nettoyé à 64 caractères), sinon le code. `TYPED` liste les refus qui portent sur
ce qui a été tapé : ils sont répondus en avertissement, car un second essai avec le bon mot
réussit, alors qu'une erreur demande qu'une chose change dans le monde.

`OpxAdmin.Server.Tell` lève un toast sur l'écran du joueur visé par
`Open77.notifications.send`, dessiné par `opx77_notify` : personne n'est déplacé en silence, mais
c'est du meilleur effort, une surface absente ne fait pas échouer une action déjà faite.

Côté client, `OpxAdmin.Client.Notice` lève les toasts de la resource via `opx77_notify` dans un
seul emplacement remplacé (`id = 'opx77_admin'`, `replace = true`) : un membre du staff qui clique
à travers un écran voit la dernière réponse, pas une pile. Sans toast (resource arrêtée ou refus),
la réponse redevient une ligne de chat et le journal le dit une fois. La réponse propre de la
resource va aussi sous la liste quand le menu l'a envoyée. Une ligne de chat (réponse, rapport,
annonce) ne porte qu'un `type` (`info`, `error`, `system`) et aucune `color` : les jetons
`.line.info`, `.line.error` et `.line.system` d'`opx77_chat` la dessinent, et aucune couleur ne
dérive ici de la palette.

## Identité et cibles

`OpxAdmin.Server.NameOf` lit le nom d'affichage vérifié par le Master, nettoyé pour une ligne de
journal ou de menu. `OpxAdmin.Server.UserOf` lit l'identifiant de compte durable : un `playerId`
est recyclé, c'est l'identifiant qui vaut d'être gardé dans une ligne d'audit.
`OpxAdmin.Server.Target` résout un id de joueur connecté ou `me` / `self`, que la console n'a pas,
et répond lui-même le refus quand il n'y en a pas ; c'est la cible des commandes qui agissent sur
un corps. `OpxAdmin.Inventory.Target` accepte en plus un citizen id, qui atteint un personnage
absent du monde : l'inventaire le résout et le vérifie lui-même. `OpxAdmin.Inventory.Resolve`
en est la forme répondue des commandes de sac et d'arme, qui refuse aussi un inventaire arrêté,
et `OpxAdmin.Inventory.HOLDER` leur paramètre de suggestion commun.

## La porte de disponibilité

`OpxAdmin.Server.Admit` répond à « peut-on faire quoi que ce soit au corps de ce joueur ? ». Agir
côté serveur sur un client qui n'est pas incarné fait planter ce client, donc deux conditions sont
exigées : un état de vie (`OpxAdmin.Server.LifeOf`, que l'écran « continuer » n'a pas) et une porte
`Open77.ready.isReady` ouverte. Elle échoue fermée quand la porte ne peut pas être lue ; `isReady`
est appelé sous `pcall` parce qu'il lève pour un id que l'hôte ne connaît pas au lieu de répondre
false. `OpxAdmin.Server.Admitted` en est la forme répondue et auditée, que prend toute commande
qui agit sur un corps ; le placement et le roster lisent `Admit` nu.

La porte garde chaque téléportation, soin, mise à mort, bascule d'invulnérabilité, holster et
livraison de véhicule. `goto` exige que la destination soit un vrai corps aussi : un joueur non
incarné se tient dans un monde de menu ; un véhicule posé à côté d'un joueur encore dans ce monde
n'atterrit à côté de personne ; demander son holster à un client non incarné, c'est parler à la
marionnette du menu. Kick et ban ne passent pas par là : ils touchent la session, pas le corps, et
un joueur coincé sur l'écran de chargement doit rester expulsable. Un changement de sac non plus :
`opx77_inventory` le fait dans ses registres et le pousse quand le joueur est là.

## Le placement : kill puis respawn

`OpxAdmin.Server.Place` déplace un joueur par kill puis respawn, jamais par une écriture de
transform : seul le respawn porte le fondu, le préchargement du streaming et la fenêtre de grâce.
Un joueur déjà mort n'est pas tué une seconde fois. Si le respawn est refusé après un kill, le
corps est à terre et n'a pas été relevé : il est réanimé là où il est tombé plutôt que laissé ainsi
(`respawn_refused`). Le kill est attribué à `opx77_admin:<why>`. La fraction de santé et la
fenêtre de grâce rendues au joueur, au respawn comme à la réanimation, viennent d'un seul
endroit, `OpxAdmin.Server.Recovery`.

`Open77.players.getHealth` répond en points absolus ; `revive` et `respawn` prennent une fraction
(`PLACEMENT.HEALTH`, bornée à 0,01..1). Les deux ne se mélangent jamais : `healthOf` rend le
maximum en points pour `setHealth`.

`observe` : il n'y a pas de caméra libre sur cette plateforme ; c'est une téléportation au-dessus
de la cible avec le noclip allumé, la cible voit l'observateur, et la réponse le dit.

## Déplacements : noclip et voyage par la carte

Les deux sont des capacités client. L'ACL décide côté serveur ; la moitié client les applique par
sa propre permission `player.travel` (`opx77_admin:travel`). Ce n'est pas ce qui empêche un client
modifié de voler — rien côté serveur ne le peut — c'est ce qui garde l'interrupteur entre les mains
du staff sur un client honnête.

`noclip` et `mapPick` (`server/players.lua`) retiennent, par joueur, le nom de la commande qui a
allumé le mode, pour qu'une permission retirée l'éteigne ; `speedChosen` retient la vitesse
choisie, pour que rallumer le noclip ne renvoie pas `NOCLIP.SPEED`. Hors de 0,1..500,
`NOCLIP.SPEED` vaut 40 m/s (`DEFAULT_SPEED`) : la moitié client n'applique une vitesse que dans
cette plage, et ses touches retombent sur la même valeur. Un fil vérifie toutes les 2 s
que cette permission est toujours accordée : `acl.reload` peut la retirer pendant que le mode est
allumé, et aucun événement ne le dit. Seul un `false` éteint ; un `nil` « impossible à dire »
laisse le mode. À l'arrêt de la resource côté serveur, chaque mode allumé est éteint : la moitié
client le fait aussi à son propre arrêt, mais ceci atteint un client qui ne s'arrête pas (un
rechargement du seul serveur). Côté client, `noclipOn` et `mapArmed` retiennent ce que la resource
a allumé, pour que son arrêt n'éteigne que cela. `OpxAdmin.Client.TravelNative` est la seule
lecture d'une fonction `Open77.travel`, partagée avec `client/controls.lua`.

Le double-clic sur la carte (`open77:map:picked`, levé par l'hôte tant que la sélection est armée)
repart comme la commande `opx77.admin.self.maptravel <x> <y> <z>` : l'ACL est résolue à nouveau à
chaque saut plutôt qu'une fois quand le geste a été armé. Un point au-delà d'un million de mètres
est une faute de frappe, pas une destination (`pointOf`). L'écriture presse-papiers est restreinte
à la seule forme de ligne que le serveur envoie (`^{ NAME = `, 160 caractères au plus).

## Contrôles de vitesse du noclip

Pas de molette : `Open77.input.isDown` lit A-Z, 0-9, F1-F12 et une liste fermée de touches
nommées, `RegisterKeyMapping` prend le même vocabulaire, et aucun appel client ne rapporte la
molette. Deux touches changent la vitesse tant que le noclip est allumé. Une touche ne fait que
choisir un nombre : il part au serveur comme `opx77.admin.self.speed`, l'ACL le résout, et la
native n'est réglée que par la réponse du serveur (`OpxAdmin.Controls.Speed`).

- Un pas est une fraction de la vitesse (`NOCLIP.STEP`) : le bas de la plage se règle finement, le
  haut se traverse en quelques secondes ; un demi-mètre par seconde au moins, arrondi au
  demi-mètre sous 10 m/s et au mètre au-dessus (`stepped`). Maintenue, une touche se répète après
  `REPEAT_DELAY_MS`, puis toutes les `REPEAT_MS`.
- `flush` n'envoie qu'après `SEND_AFTER_MS` de silence, donc une touche maintenue est une commande
  et non trente. Ce délai n'est jamais inférieur à `RATE.ACTION_MS` + 100 ms (`SEND_FLOOR_MS`) :
  le serveur refuserait une seconde commande mutante dans son plancher.
- Pendant `ANSWER_WINDOW_MS` après un envoi, la réponse est prise comme celle des touches
  (`OpxAdmin.Controls.Answered`) : acceptée, elle n'est pas toastée, le bandeau montre déjà le
  nombre ; refusée, elle remet la lecture à la vitesse du serveur et est toastée. `sent` reste
  quand le serveur applique une vitesse : la réponse de la commande arrive après ce push.
- `tick` (`TICK_MS`) suit la native : un noclip éteint sous nos pieds (autre resource, mort, la
  native elle-même) n'est cru qu'après `OFF_READS` lectures « éteint » et `OFF_SETTLE_MS` depuis
  l'allumage, car la native peut ne pas rapporter un changement dans la frame où elle l'a pris. Un
  client sans la lecture `isNoclip` compte comme allumé : la commande serveur fait foi.

Le bandeau d'`opx77_prompts` (`sync`) montre les contrôles tant que le noclip est allumé et le
personnage vivant, et l'indice du double-clic tant que la carte est armée. Le groupe noclip a la
priorité `NOCLIP_PRIORITY` (50), au-dessus de ce qu'une resource de gameplay affiche : un membre du
staff qui vole est la première chose à lire. Les lignes présentes dépendent des touches
enregistrées, d'où la `signature` (vitesse et présence des trois touches) ; les noms de touches
sont ceux d'`opx77_prompts`, qui suit une réassignation. L'état affiché est marqué avant que
l'appel n'aboutisse, pour que le tick suivant ne renvoie pas le même groupe, et un refus est
journalisé une fois, non réessayé. Les appels partent dans un thread, car un appel d'export est
attendu ; chaque thread envoie son appel avant que le suivant ne tourne, donc un `hide` en file
derrière un `show` n'est jamais sauté. Un `opx77_prompts` redémarré a perdu ses groupes : on remet
les nôtres ; à l'arrêt de cette resource, il retire lui-même les groupes d'un propriétaire arrêté.

## Touches

Chaque touche est déclarée par `RegisterKeyMapping` (`OpxAdmin.Keys.Register`) : l'onglet des
raccourcis du menu pause la liste sous son nom localisé, lu au démarrage de la resource, et le
joueur la réassigne là. Rien ici ne lit une touche ni ne décide : une touche fait ce que fait sa
commande. Les identifiants `opx77_admin.menu`, `opx77_admin.noclipFaster`,
`opx77_admin.noclipSlower` sont stables : la réassignation d'un joueur est stockée sous eux. Un
refus coûte une ligne de journal ; la commande marche toujours.

- Une pression pendant qu'une autre surface tient le clavier (`OpxAdmin.Keys.Captured`, sur
  `Open77.input.isCaptured` : le chat, un formulaire, le menu pause) ne fait rien ; les touches de
  vitesse relâchent aussi leur répétition quand le clavier est pris. Un relâchement n'est jamais avalé : une touche
  relâchée derrière une surface ne doit pas rester tenue ici. Le cinquième argument n'est passé
  que s'il existe : c'est lui qui fait d'un mapping un mapping maintenu.
- Deux formes de réponse sont documentées : le guide des touches répond `true, key`, la référence
  d'API la touche seule ; les deux valent enregistrement, `false|nil, reason` vaut refus.
- `OpxAdmin.Keys.Effective` lit `Open77.input.keyFor` pour nommer la touche réellement assignée ;
  nil quand le mapping est éteint ou refusé, pour qu'un indice sans touche ne dise rien.
  `open77:keybinds:changed` relance les écouteurs : la ligne Fermer du menu et le bandeau.
- La touche du menu : menu ouvert, elle le ferme localement, ce qui n'accorde rien ; menu fermé,
  elle envoie la ligne `/opx77.admin`, donc l'hôte résout `command.opx77.admin` d'abord. Elle est
  enregistrée pour tout joueur : le client ne connaît pas l'ACL.

## Le canal de commande

`OpxAdmin.Client.Execute` envoie les jetons exactement comme la boîte de chat, par
`open77:command:execute` : ce n'est pas une porte dérobée, c'est la même porte, utilisée par un
menu au lieu d'un clavier. Le transport refuse d'emblée les caractères de contrôle et un jeton de
plus de 256 octets : chaque jeton est nettoyé, découpé sur les espaces et coupé à 256 octets sans
casser un caractère ; une ligne vide ou de plus de 32 jetons n'est pas envoyée.

Le répartiteur accuse réception d'une commande mise en file sur le même événement que la réponse,
et seule sa formulation anglaise les distingue : `QUEUE_ACK` est le fragment que partagent les deux
formulations connues (`queued by <resource>` et `command '<name>' queued by resource <resource>`),
non ancré ; voir `opx77_chat/docs/unknowns.md`. `awaiting` retient quand le menu a envoyé chaque
commande : une réponse arrivée dans les 15 secondes est écrite sous la liste, car d'autres
resources partagent les événements de résultat. Un refus de l'hôte (`unknown_command`,
`permission_denied:`) est mis en mots ; `opx77_chat` le toaste aussi. `opx77_chat` n'imprime aucun
résultat accepté : le rapport d'une commande liée envoyée par le menu (les détenteurs d'un objet)
devient ici une ligne de chat, et la ligne sous la liste n'en garde que la première ligne.

## Appels d'export

`OpxAdmin.Inventory.Call` (serveur) et `OpxAdmin.Client.Call` (client) suivent la même règle : seul
l'envoi (`Open77.exports.call`) est sous `pcall`, car `promise:await()` cède la main et une
coroutine ne peut pas céder à travers un `pcall` ; la promesse de l'hôte est un userdata, testée
par présence, jamais par son type Lua ; chaque appel tourne dans un thread à lui, car un handler de
commande s'exécute sous le `pcall` de `OpxAdmin.Server.Command`.

- Serveur : `UNAVAILABLE` liste les raisons de l'hôte qui veulent dire « l'inventaire n'est pas là
  pour répondre » (`export_not_found`, `export_resource_stopped`, `export_timeout`, ...), qui
  deviennent `inventory_unavailable` ; toute autre raison est `refused`. Une réponse `ok ~= true`
  est traduite par `CODES` (`caller_denied` -> `inventory_denied`, `no_room` -> `bag_no_room`,
  ...) ; un code inconnu devient `refused`, avec le code de l'inventaire comme raison d'audit.
  Les refus qui ne demandent aucun appel (cible invalide, inventaire arrêté) sont répondus avant
  de lancer le thread (`OpxAdmin.Inventory.Resolve`), et un nombre tapé passe par
  `OpxAdmin.Inventory.Count`.
- Client : le troisième retour dit si la cible a répondu ; un refus (toute réponse `ok ~= true`,
  forme sans `ok` comprise) fait autorité, un appel qui n'a jamais abouti ne dit rien.
  `Open77.exports` est toujours une table : seul l'envoi est gardé. Les dépendances souples manquantes (`opx77_menu`, `opx77_input`)
  sont signalées une fois par resource (`OpxAdmin.Client.Need`), pas une fois par clic.

L'avertissement « `opx77_inventory` is not running » est émis cinq secondes après le chargement,
dans un thread : au chargement de ce fichier, une resource listée après celle-ci ne tourne pas
encore.

## opx77_inventory, seule autorité sur ce que porte un personnage

`opx77_inventory` est la seule autorité sur ce que porte un personnage, armes comprises. Ses
exports serveur prennent un id de joueur ou un citizen id, revérifient chaque argument et écrivent
à travers `opx77_core`. Une action de staff sur un sac est donc une commande de cette resource,
gardée par l'hôte sur `command.opx77.admin.…`, auditée ici et répondue dans nos toasts, dont le
handler appelle ces exports. Ouvrir le sac d'un autre personnage sur un écran de staff et lister
les détenteurs d'un objet n'ont pas d'export — le second est une requête que l'inventaire fait avec
une portée du core qu'il est seul à détenir — : le menu pilote pour cela les commandes de
l'inventaire (`LINKS.INVENTORY_OPEN`, `LINKS.INVENTORY_HOLDERS`), comme il pilote celles
d'`opx77_core` pour un métier ou de l'argent. Il n'y a pas de repli sur le relais d'armes sans
l'inventaire : une arme posée dans un slot sans objet est exactement l'arme non justifiée que
l'inventaire retire, ou garde non enregistrée.

`OpxAdmin.Inventory.Catalog` lit `GetItems` page par page (au plus 64 pages) et garde le résultat :
c'est le `data/items.lua` et le `data/weapons.lua` de l'inventaire, qui ne changent qu'avec lui. Le
cache est oublié quand il démarre ou s'arrête (`open77:resource:started` / `stopped`) et au bout de
`CACHE_MS`. Une arme est un objet portant `weapon = { class, ammo }`, une munition un objet portant
`ammoMax`, un plein. `OpxAdmin.Inventory.Weapon` accepte le nom avec ou sans le préfixe
`weapon_`. `OpxAdmin.Inventory.LabelOf` retombe sur le nom : un objet retiré du catalogue reste
dans les sacs jusqu'à ce qu'on l'enlève, et c'est aussi pourquoi `inventory.remove` accepte tout
nom bien formé. Lire un sac (`inventory.view`) est audité : ce sont les affaires de quelqu'un,
comme la fouille propre de l'inventaire.

## Armes et munitions

Une arme est un objet de l'inventaire : une unité dans un sac portant un numéro de série et ses
cartouches, que le joueur dégaine en l'utilisant. Une munition est un objet à part, une pile que le
joueur dépense sur l'arme dégainée qui la prend. Aucune commande ne met un record dans un slot du
jeu ni n'écrit de cartouches sur un objet : l'inventaire retire, toutes les `WEAPONS.SCAN_MS`,
toute arme qu'aucun sac ne justifie, si bien qu'une arme remise autrement ne durerait pas et ne
serait pas enregistrée.

- **Don** (`weapon.give`) : l'arme est donnée vide (`{ ammo = 0 }`). Avec un nombre de munitions,
  `giveWithAmmo` donne les deux ou aucun : le sac est lu d'abord pour vérifier le poids et les
  slots des deux ensemble (`CanCarry` ne pèse qu'un objet à la fois) et pour reconnaître, par son
  numéro de série, l'arme qui vient d'être ajoutée d'une copie déjà présente. L'inventaire décide
  en dernier : s'il refuse ensuite les munitions, l'arme ajoutée est reprise (`RemoveItem` avec
  ses métadonnées), et si elle ne peut pas l'être la réponse est `give_partial`.
- **Munitions** (`weapon.giveammo`) : un objet de munition par son nom, ou une arme désignant la
  munition qu'elle prend ; sans nombre, un plein.
- **Recharge** (`weapon.ammo`) : une pile par type de munition, une seule fois quel que soit le
  nombre d'armes du sac qui le prennent ; aucune arme n'est écrite.
- **Retrait** (`weapon.remove`) : sans défaut, car prendre toutes les armes n'est jamais ce que
  voulait dire un argument oublié ; par nom et par nombre, pas par slot, car un slot lu un instant
  plus tôt peut contenir autre chose ; l'inventaire rengaine lui-même une arme dégainée dont
  l'objet a quitté le sac.
- **Lecture** (`weapon.read`) : les armes du sac, leurs cartouches, et celle qui est dégainée
  (`GetHeldWeapon`), reconnue par son numéro de série.

Recharge, retrait et lecture commencent par `weaponsInBag` : le catalogue, l'arme nommée s'il y en
a une, puis le sac, chaque échec répondu et audité sous l'événement de la commande.

**Le holster, dernier usage du relais.** Une seule chose reste sur `Open77.weapons`, le relais de
la plateforme vers la moitié client d'`open77_weapons` : rengainer, parce que l'inventaire n'a pas
d'export pour cela et que cela ne change aucun objet. Une étape du relais répond en deux temps :
`holster` rend un identifiant de requête, gardé dans `pending`, et `open77:weapons:completed` porte
le verdict du client (`request_timeout` devient `weapon_no_answer`). Un relais qui ne répond jamais
est un délai dépassé côté plateforme ; le balayage borne tout de même `pending` (`PENDING_MS`) au
cas où la complétion n'atteindrait jamais cette VM.

## Véhicules

L'hôte limite chaque mutation de véhicule à la resource qui l'a créé : `server/vehicles.lua` ne
peut toucher que ce qu'il a fait apparaître, et le dit (`not_ours`) plutôt que de répondre
« 0 retiré ». `spawned` retient ce que la resource a fait apparaître et pour qui ; `prune` oublie
les lignes dont l'hôte ne connaît plus le véhicule, quel que soit celui qui l'a retiré, avant de
compter le plafond `VEHICLES.PER_OWNER`. `remove mine` et `cleanup` comptent de la même façon : un
véhicule que l'hôte ne connaît déjà plus (`no_vehicle`) est oublié sans être compté « laissé en
place », et `remove mine` ne répond une erreur que si un véhicule est resté (occupé, ou refusé par
l'hôte) sans qu'aucun ne soit retiré ; n'avoir rien à retirer est un succès. L'instantané serveur porte `x`, `y`, `z` et `bucket` au
premier niveau, et les ids d'occupants peuvent arriver en chaînes.

`near` désigne le véhicule où l'opérateur est assis, sinon le plus proche dans son bucket à moins
de `VEHICLES.NEAR_RADIUS`, lu dans l'instantané vivant et jamais dans une liste qu'un menu a
dessinée quelques secondes plus tôt. Retirer un véhicule est refusé avec quelqu'un à bord :
retirer un véhicule occupé lâche ses occupants là où il était, et le cas qui compte est celui où
quelqu'un est monté après que le menu a été dessiné. Une réparation `full` ou `mechanical` peut
refaire apparaître le véhicule : l'occupation est lue au moment de l'appel, et seules les portées
de `VEHICLES.OCCUPIED_REPAIRS` passent avec quelqu'un à bord. Les flags : `maskOf` n'accepte qu'un
flag de `VEHICLES.FLAGS` dont l'hôte connaît le masque, et la mise à jour est un
lire-modifier-écrire sur les bits vivants, parce que le patch remplace l'ensemble.

## Modération

La plateforme refuse net une raison de déconnexion au-delà de 127 octets UTF-8
(`KICK_REASON_BYTES`) : la raison est coupée en octets sans casser un caractère
(`OpxAdmin.Text.Bytes`). Une durée de ban s'écrit `30m`, `12h`, `7d`, `3600s`, ou `perm` /
`permanent`, jusqu'à 3650 jours. Un nombre nu n'est pas une durée : `/ban 7 3 strikes` est une
raison, pas trois secondes. Un mot qui ressemble à une durée mais sort de la plage est refusé
(`bad_duration`) : refuser vaut mieux que bannir pour toujours. L'hôte écrit le ban avant de
déconnecter qui que ce soit, et répond false s'il n'a pas pu.

## Destinations, annonces et lectures

La liste configurée (`LOCATIONS`) est la liste durable. Les destinations ajoutées en jeu vivent
dans `Open77.state`, que l'hôte transporte à travers un rechargement et abandonne à l'arrêt : un
ajout en jeu est un brouillon, et `opx77.admin.self.pos` est la manière dont un endroit devient une
ligne de configuration. `seed` reconstruit la liste ; un ajout en jeu sous un nom configuré le
remplace pour la durée du run. L'état transporté est une entrée non fiable : un rechargement peut
avoir changé ce fichier, donc une forme que cette version ne connaît pas (`STATE_PROTOCOL`) est
refusée entière plutôt qu'adoptée à moitié.

L'heure et la météo ne sont pas ici : `opx77_weather` les possède, ses commandes sont déjà gardées
par l'ACL, et le menu pilote ces commandes plutôt que de monter une seconde autorité.

Une ligne du roster (`OpxAdmin.Server.RosterRow`) ne porte pas de personnage : le citizen id et le
nom vivent dans la VM d'`opx77_core`, que rien ici ne peut interroger ; la ligne « fiche » du menu
lance `opx77.where`. `WATCHED` liste l'ensemble OPX//77 et les paquets de la plateforme sur
lesquels celle-ci s'appuie ou avec lesquels elle entre en collision : aucun moyen n'existe
d'énumérer les resources, `GetResourceState` ne répond que pour un nom déjà connu.

## L'audit

`OpxAdmin.Server.Audit` enregistre une action staff dans deux puits : une ligne dans le journal de
la plateforme, dans la forme `[audit] event=... severity=...` qu'écrit `opx77_core`, pour qu'un
seul grep trouve les deux, et un anneau en mémoire (`ledger`, `AUDIT_ENTRIES`, au moins dix) que
lit `opx77.admin.read.audit` via `OpxAdmin.Server.Recent`. La ligne de journal est
l'enregistrement ; l'anneau meurt avec le processus. Un refus est journalisé en `warn`. `event` est
stable et greppable (`admin.player.kill`), `detail` est en anglais.

## Le menu, côté serveur

Le menu ne décide rien. Ce qu'il montre vient d'ici, et tout ce qu'il fait est une ligne de
commande envoyée par `open77:command:execute`, si bien que l'hôte résout `command.<name>` pour
chaque ligne exactement comme pour une commande tapée ; un client qui forge une ligne reçoit la
réponse d'une commande tapée. L'ouverture du menu est la réponse de `/opx77.admin` : aucune ligne
de chat à chaque ouverture.

- **`opx77_admin:refresh`** redemande une liste (roster, destinations, carte d'accès, catalogue,
  sac). Un événement réseau ne porte aucune autorisation : il est revérifié contre la permission de
  l'ouvreur (`OPENER`, `command.opx77.admin`) — qui peut ouvrir le menu peut lire ce qu'il dessine.
  Il échoue fermé : sans lecteur d'ACL rien ne distingue le staff des autres, et la commande
  ouvreuse reste là pour tout rafraîchir. Les piles d'un sac sont les affaires de quelqu'un :
  elles exigent en plus la permission de voir ou d'enlever. `RATE.REFRESH_MS` borne la cadence par
  joueur et par sujet, par `OpxAdmin.Server.Cooled`, avant la vérification de la permission.
- **La carte d'accès** (`accessOf`) : un indice de dessin et rien de plus. Seuls les grants
  voyagent : un `false` coûterait deux nœuds de valeur et ne dit rien de plus qu'un `nil`.
- **Envois par morceaux** (`pushChunks`, `ROSTER_CHUNK` = 20 lignes) : l'hôte abandonne sans un
  mot un événement de plus de 1 024 nœuds de valeur, et une ligne en compte une douzaine. Roster,
  destinations (dont le nombre ajouté en jeu n'a pas de plafond), catalogue et sac passent tous
  par là. Le client recolle les morceaux (`collect` ; roster et destinations par leur propre
  tampon) et n'adopte la liste qu'au dernier morceau (`done`). Ne pas les supprimer.

## Le menu, côté client

Chaque écran est son propre `open` d'`opx77_menu`, pas un sous-menu d'un grand arbre :
`opx77_menu` refuse une spec de plus de 400 lignes sur tout l'arbre, et un roster de trente joueurs
avec vingt actions chacun la dépasse. La pile d'écrans (`stack` : écran, argument, curseur) est
tenue ici. Un niveau refuse plus de 200 lignes : une liste en montre au plus `MAX_LISTED` (190),
pour laisser la place à la navigation. Une liste de catalogue (véhicules, armes, objets) est
paginée à `PAGE_ROWS` (20) avec une ligne « Plus » : `opx77_menu` vérifie chaque ligne d'une spec
dans un seul handler, à quelques centaines d'instructions VM par ligne, et l'hôte arrête un handler
client au-delà de 10 000 instructions (`paged`). Ne pas retirer cette pagination.

- Les lignes grisées passent par trois aides : `denied` (l'ACL refuse la commande où mène la
  ligne), `offline` (l'inventaire est arrêté) et `unavailable` ; une liste vide montre la ligne
  `empty`. `takeDown` ferme le handle ouvert, pour un formulaire comme pour une fermeture.
- `drawn` est incrémenté à chaque dessin : un `open` lent qui a perdu la course ne réclame pas le
  handle. Un dessin en place tente `update` et retombe sur `open`.
- Sans lecteur d'ACL sur l'hôte (`aclKnown == false`), toutes les lignes sont actives et l'hôte
  répond pour chacune.
- Rafraîchissements (`push`) : quitter la racine redemande la carte d'accès, pour qu'un
  `acl.reload` se voie sans rouvrir ; roster, destinations, catalogue (s'il manque ou a échoué) et
  sac sont redemandés à l'entrée de leurs écrans. Un sac est toujours relu : il change entre deux
  visites. Après une commande, `OpxAdmin.Menu.Run` redemande la liste concernée 1,2 s plus tard,
  le temps qu'elle aboutisse. Le catalogue est vidé à chaque ouverture : il suit sur son propre
  événement, et une lecture avant lui dessinerait l'ancien.
- « Ouvrir le sac à côté du mien » ferme le menu (`closeAfter`) : l'écran de l'inventaire prend le
  clavier.
- Tuer, expulser, bannir, tout désarmer, vider un sac, le nettoyage des véhicules, une annonce et
  la sauvegarde de tous les personnages passent par un écran de confirmation où Annuler est la
  première ligne ; pas de Retour sous lui, ce serait une deuxième façon de dire non.
- La ligne sous la liste est limitée à 120 caractères par `opx77_menu` et un listing fait plusieurs
  lignes : `OpxAdmin.Menu.Status` garde la première, coupée à 116 octets par `OpxAdmin.Text.Bytes`, qui ne
  coupe jamais un caractère UTF-8 en deux (un accent coupé est un octet invalide dans la page) ; le
  chat a tout. Sans menu
  ouvert, elle est gardée pour le prochain écran.
- Fermeture (`opx77_admin:row`, action `close`) : une fermeture `reopened`, ou d'un handle qui n'est
  plus le nôtre, vient d'un écran remplacé et peut arriver avant le nouveau handle : ignorée.
  `back` dépile un écran. Pendant un formulaire, la pile est gardée.
- `opx77_admin:open` reçu alors que le menu est ouvert le ferme : la commande ouvreuse est un
  interrupteur. À l'arrêt de la resource, le menu est fermé : `opx77_menu` et `opx77_input`
  balaient un propriétaire arrêté, mais pas instantanément.
- Les lignes d'armes : toutes sauf « Rengainer » ont besoin de l'inventaire ; « Rengainer » a
  besoin du relais (`session.weapons`). Les armes sont groupées par les classes de
  `data/weapons.lua` dans leur ordre, puis toute classe que ce fichier ne nomme pas, sous sa clé.
- N'importe quelle resource cliente peut lever `opx77_admin:open`, `:travel`, `:row` ou `:form` :
  `open` ne lui donne qu'un menu dont chaque ligne est une commande que l'hôte lui refuse, `travel`
  rien qu'elle ne puisse faire avec sa propre `player.travel`, et `row` / `form` vérifient la forme
  et le propriétaire (`payload.owner == OpxAdmin.Client.RESOURCE`).

## Formulaires

Ce qu'une ligne de menu ne peut pas porter — une raison, un montant, un point, un nombre — est
demandé par `opx77_input` (`OpxAdmin.Forms.Open`). Le menu est retiré d'abord
(`OpxAdmin.Menu.Suspend`) : un formulaire et une liste qui lisent tous deux les flèches, c'est un
de trop ; il revient là où il était quand le formulaire est répondu dans un sens ou dans l'autre.
La réponse devient une ligne de commande comme n'importe quelle ligne. `menu()` lit
`OpxAdmin.Menu` à l'appel, car `client/menu.lua` charge après `client/forms.lua`.

- Job et gang partagent une forme (`groupForm`) ; le grade est tapé, car sa plage dépend du groupe.
  Les options viennent de `GetJobs` / `GetGangs` d'`opx77_core`, les types d'argent de
  `GetSharedConfig`.
- Un slider répond un flottant, et `%d` lève sur un nombre à partie fractionnaire : les points de
  santé passent par `math.floor`.
- Les sélecteurs passent leur ligne au formulaire : `t` la cible, `n` l'objet, `l` son libellé,
  `c` le nombre dans la pile (retrait), `x` le plein (munitions, valeur de départ).
- Un handle différent du formulaire ouvert est ignoré.

## Indexer le catalogue par parties

L'hôte vérifie la durée de chargement d'un script toutes les 10 000 instructions de la VM et annule
tout l'ensemble de resources quand une vérification tombe après son échéance : aucun fichier ne
doit en atteindre une. Une ligne de `data/vehicles.lua` coûte environ 110 instructions ;
`shared/catalog.lua` n'en indexe aucune et publie `OpxAdmin.Catalog.PART` (68), et chaque partie
`shared/catalog-<n>.lua` appelle `OpxAdmin.Catalog.IndexVehicles(PART)` sur les lignes suivantes.
La dernière appelle `OpxAdmin.Catalog.FinishVehicles`, qui indexe tout ce qui reste : une partie
manquante coûte du temps de chargement, jamais un véhicule, et quand il reste plus d'une part, une
ligne de `OpxAdmin.Catalog.problems` demande d'ajouter une partie au manifeste. Ne pas fusionner
ces fichiers.

Une ligne mal formée (nom, record, classe, doublon) est écartée et nommée dans
`OpxAdmin.Catalog.problems`, que le serveur journalise au démarrage, plutôt que de lever au
chargement. Les deux moitiés lisent l'index : le serveur pour refuser un véhicule qui n'est pas une
ligne, le client pour dessiner les listes, les deux pour grouper les armes.

`data/vehicles.lua` est la liste blanche : un record qui n'y figure pas n'atteint jamais
`Open77.vehicles.create`. La plateforme n'a aucun appel serveur qui énumère les records de
véhicules, d'où la copie depuis le catalogue que livre `open77_admin` (README « Catalogues »).
`data/weapons.lua` ne liste plus d'armes : une classe n'y donne qu'un ordre de menu et un `LABEL`,
et `KEY` correspond à `CLASS` chez l'inventaire.

## Textes et coercitions

Tout ce qu'une commande lit arrive en chaîne tapée par une personne : chaque nombre passe par
`OpxAdmin.Text.Finite` et chaque phrase par `OpxAdmin.Text.Clean`.

- `MAGNITUDE` (2^53) est la plus grande grandeur acceptée : au-delà, `%d` n'a plus de forme
  entière. `value ~= value` est le test de NaN ; NaN et les deux infinis sont refusés.
- `OpxAdmin.Text.Clean` remplace les caractères de contrôle par des espaces : un saut de ligne dans
  un nom ou une raison forgerait une ligne de journal entière. `span` borne le parcours à quatre
  octets par caractère, pour qu'une suite d'octets de continuation ne rende pas la coupe illimitée.
- `OpxAdmin.Text.Bytes` coupe en octets sans couper un caractère : la plateforme mesure une raison
  d'expulsion en octets et refuse l'appel entier au-delà de sa limite.

`OpxAdmin.Locale.Get` (le raccourci global `locale`) ne répond jamais nil : une traduction manquante
retombe sur `en`, puis sur la clé ; un `{name}` sans valeur reste écrit tel quel.
`OpxAdmin.Locale.Set` accepte un code inconnu, car les catalogues s'enregistrent après le module.
Les lignes de journal et les réponses à la console restent en anglais (`OpxAdmin.Locale.English`).
`OpxAdmin.Locale.register` garde son nom en minuscules : les fichiers de traduction des opérateurs
l'appellent. Les libellés des invites (`admin.prompt.*`) sont courts à dessein : la bande
d'`opx77_prompts` ne passe jamais à la ligne.

## Clés résolues à l'exécution

Aucune clé orpheline : les clés composées (`'admin.state.' .. state`) et celles de `ERRORS` sont
nommées littéralement ailleurs dans le code.

## Limites connues

- `OpxAdmin.Catalog.problems` n'est journalisé que par le serveur ; les données étant les mêmes,
  sa ligne couvre le client.
