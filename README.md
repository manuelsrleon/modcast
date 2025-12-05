# modcast
## What is modcast?
Proof of Concept of an elixir-based platform-agnostic P2P mod sharing system for videogames. Part of an assignment for the Software Architecture assignment @ FIC (UDC). 

modcast intends to be a decentralized, hands-free aproach to syncing cosmetic modifications across the clients of a P2P hosted multiplayer match, coop game or generally any type of custom content enabled multiplayer game.

In the advent of platform lock-ins, more resilient, decentralized and user-controlled systems are desirable, so modcast aims to be the component that enables developers to incentivize users to explore their creativity by providing an opportunity to show their creations without worrying about hosting costs or implementation complexity. 
modcast tries to abstract that complexity by providing developers a module that will automatically sync game resources between clients.

## Why P2P? 
After studying the architectural alternatives

## Main components (subject to change)

### Modcast Mod File (MMF.zip)
TBD
### Mod Definition Schema (MDS.xml)
TBD
### Sync Status Ledger (SSL)
TBD
### Modcast Custom Content Storage (CCS)
Synced game resources will also be stored in the Modcast Custom Content Storage. The entire .zip file, including the MDS.xml will be hashed. If two hashes are equal, files are assumed to be the same, which will mean that it will be displayed across 
### Modcast SyncAPI (MSAPI)
The Modcast SyncAPI provides the developer extensions to their game engine that enable him to, as simply as possible, to interface with the custom content. It has to be enough abstract to be simple to use, but also provide game-agnostic interfacing that ensures that every game genre and type. For this we've opted to make modcast file-based and leave implementation details up to the developer.
### Game State Component (GSC)
The Game State Component handles all the syncing logic between client. It is called upon by the SyncAPI functions, and uses the File Transfer Component to send and receive files. The GSC also syncs the SSL which will be exposed to the game, so the game can load the required assets while necessary. 

There is a table that has the following attributes, and must be in sync between all clients
| attribute | type     | Description                                                                                                                                                   | Example value                        | Example                                                                                                 |
|-----------|----------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------|---------------------------------------------------------------------------------------------------------|
| player_id | GUID     | Identifies the player in a given game                                                                                                                         | c04671f8-37d3-4d76-82e3-10816abf6950 | Han Seoul-Oh : 12312312                                                                                 |
| asset_id  | GUID     | Identifies the asset in regards to the game.                                                                                                                  | 9623745a-5453-4eee-9c5f-cfb246fbfa19 | A car model you can buy: RX7                                                                            |
| entity_id | GUID     | Identifies the given instance of an asset. This identifies the asset in the game world. Two identical cars can be different as they exist as separate entity. | b8ff63cb-9991-4a1b-8fa0-7ca382632a6e | My own car in the game: My Fast and Furious' Tokyo Drift Mazda RX7 VeilSide Fortune                     |
| hash      | MD5 Hash | Hash that will be used to negotiate what files need to be transferred and what file will be chosen to replace the in-game one.                                | 7e1e5d5167092343e71d6eef1455b924     | The hash of the file that corresponds to the mod I assigned to my own car: MD5(VeilSide_RX7_by_Han).zip |

### File Transfer Component (FTC)
### 
#### ModcastManager.init(ModcastConf)
####
### Modcast Network Test (MNT)

## Team members
|                               |UDC login          | GitHub username|
|-------------------------------|-------------------|----------------|
|David Javier Montes Fernández  |david.j.montes     |deivisi         |
|Manuel Santamariña Ruiz de León|manuel.santamarina |manuelsrleon    |
|Roi Millán Míguez              |roi.millan.miguez  |roimm1          |
|Pablo Masián Carro             |pablo.masian.carro |pablomasian     |
|Antón Pernas González          |antonio.pernasg    |antonioPernas   |

## Supervised by 
David Cabrero Souto
