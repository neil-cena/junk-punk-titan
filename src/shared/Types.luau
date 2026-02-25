--!strict

export type RoleName = "Scrapper" | "Fixer" | "Enforcer"
export type BuildingType = "Turret" | "Drill" | "Wall"

export type RoleDefinition = {
	speedMult: number,
	repairMult: number,
	damageMult: number,
}

export type TheftData = {
	dismantleProgress: number,
	isBeingDismantled: boolean,
	attachedEnemy: Model?,
}

export type LegacyBuff = {
	scrapGatherMult: number,
	reloadSpeedMult: number,
}

export type PurchaseResponse = {
	success: boolean,
	cost: number,
	remainingScrap: number,
	reason: string?,
}

export type BlueprintData = {
	id: string,
	buildingType: BuildingType,
	position: Vector3,
	rotation: number,
	ownerUserId: number,
	isFinished: boolean,
}

export type ResourceType = "Scrap" | "StormHardenedSteel"

export type SessionStats = {
	scrapGathered: number,
	ratsKilled: number,
	buildingsLost: number,
	stagesCompleted: number,
	wavesCompleted: number,
	timeElapsed: number,
}

return {}
