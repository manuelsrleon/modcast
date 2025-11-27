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

#### ModcastManager.init(ModcastConf)
####
### Modcast Network Test (MNT)

## Team members
|                               |UDC login          | GitHub username|
|-------------------------------|-------------------|----------------|
|David Montes                   |david.j.montes     |deivisi         |
|Manuel Santamariña Ruiz de León|manuel.santamarina |manuelsrleon    |
|Roi Millán Míguez              |roi.millan.miguez  |roimm1          |
|Pablo Masián Carro             |pablo.masian.carro |pablomasian     |
|Antón Pernas González          |antonio.pernasg    |antonioPernas   |

## Supervised by 
David Cabrero Souto
