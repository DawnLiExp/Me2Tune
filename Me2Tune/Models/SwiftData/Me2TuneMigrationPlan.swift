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
            // 未来追加：Me2TuneSchemaV2.self
        ]
    }

    static var stages: [MigrationStage] {
        []
    }
    // 未来追加：static let migrateV1toV2 = MigrationStage.lightweight(...)
}
