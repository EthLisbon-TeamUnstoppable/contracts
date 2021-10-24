# MetalJustice

## Overview
MetalJustice is a fair and decentralized system for resolving personal disputes between two parties.

## Contract actors
 - Requester - a person who creates the dispute. During a dispute two people provide some collateral. The winner receives the whole collateral.
 - Opponent - a person who accepts the dispute from a requester.
 - Judges - resolve disputes by checking proofs provided by requesters and opponents. Anyone can become a judge by staking ether to the smart contract. If a judge receives too many appeals, their stake will be lost. So judges are incentivised to resolve cases fairly. Participating judges earn a commision from each resolved case.

## Judging protocol
 1. Case creation
 A requester creates a case by submitting a collateral, case description, opponents address and the hash of their side of the proof. 
 2. Case acceptance
 An opponent accepts a case by matching the requester's collateral and providing the hash of their side of the proof.
 3. Proof disclosure
 To ensure that opponents do not ignore cases based on the provided proof, only proof hashes are submitted initially. Once both participants are commited to the dispute, they can disclose proofs for judging to begin. The proofs may be simply a text description or a link to some materials. 
 4. Judging
 Once both participants submit their proofs, judging can begin. Judges are assigned randomly to a case selected uniformly from the list of available judges.
 Each judge must submit their decision. The winner is determined by simple majority.
 5. Appeal
 Once a decision is made by the judges, any of the participants can appeal the decision. To initiate the appeal they must provide more collateral. And in case of an appeal the number of judges will be increased. When an appeal is submitted, a new set of judges is assigned to the case and judging begins again.
 6. Finalization
 If a decision is reached and no appeal was made, the case is finalized. Judges receive their commision and the winner receives the rest of collaterall.

## DApp
The protocol is fully decentralized, without a backend. 
The front-end UI can be seen here [Figma UI](https://www.figma.com/file/LKBhUJKBFO2JtgLa1xx0n0/Private-Justice?node-id=0%3A1)
Source code of the DApp is provided here [MetalJustice](https://github.com/EthLisbon-TeamUnstoppable/MetalJustice).
