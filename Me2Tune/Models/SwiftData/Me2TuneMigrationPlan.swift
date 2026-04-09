//
//  Me2TuneMigrationPlan.swift
//  Me2Tune
//
//  SwiftData 迁移计划 - 管理所有 Schema 版本升级路径
//

import SwiftData

enum Me2TuneMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            Me2TuneSchemaV1.self,
            Me2TuneSchemaV2.self,
        ]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    // SDPlaybackState 从 schema 中移除后，使用 lightweight migration 自动清理旧表
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: Me2TuneSchemaV1.self,
        toVersion: Me2TuneSchemaV2.self
    )
}
