import Foundation
@preconcurrency import SQLite

// MARK: - Appointment Prep CRUD Operations
extension DatabaseManager {

    // MARK: - Save / Update
    /// Inserts or replaces an appointment prep record (encrypted blob + plaintext sort columns).
    func saveAppointmentPrep(_ prep: AppointmentPrep) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        do {
            let encrypted = try encryptData(prep)

            let insert = appointmentPrepsTable.insert(or: .replace,
                prepId <- prep.id.uuidString,
                prepEncryptedData <- encrypted,
                prepStatus <- prep.status.rawValue,
                prepCreatedAt <- Int64(prep.createdAt.timeIntervalSince1970),
                prepUpdatedAt <- Int64(prep.lastModified.timeIntervalSince1970)
            )

            try db.run(insert)
            AppLog.shared.database("Saved appointment prep \(prep.id.uuidString)")
        } catch {
            AppLog.shared.error("Failed to save appointment prep: \(error.localizedDescription)", error: error, category: .database)
            throw DatabaseError.encryptionFailed
        }
    }

    // MARK: - Fetch All
    /// Returns all saved appointment preps, newest first.
    func fetchAppointmentPreps() async throws -> [AppointmentPrep] {
        guard let db = db else { throw DatabaseError.connectionFailed }

        var results: [AppointmentPrep] = []
        do {
            let query = appointmentPrepsTable.order(prepUpdatedAt.desc)
            let iterator = try db.prepareRowIterator(query)
            while let row = try iterator.failableNext() {
                do {
                    let prep = try decryptData(row[prepEncryptedData], as: AppointmentPrep.self)
                    results.append(prep)
                } catch {
                    // Skip records that can't be decrypted rather than failing the whole load.
                    AppLog.shared.database("Skipping undecryptable appointment prep \(row[prepId])", level: .warning)
                }
            }
        } catch {
            throw DatabaseError.decryptionFailed
        }
        return results
    }

    // MARK: - Fetch Single
    func fetchAppointmentPrep(id: UUID) async throws -> AppointmentPrep? {
        guard let db = db else { throw DatabaseError.connectionFailed }

        do {
            let query = appointmentPrepsTable.filter(prepId == id.uuidString)
            if let row = try db.pluck(query) {
                return try decryptData(row[prepEncryptedData], as: AppointmentPrep.self)
            }
            return nil
        } catch {
            throw DatabaseError.decryptionFailed
        }
    }

    // MARK: - Delete
    func deleteAppointmentPrep(_ prep: AppointmentPrep) async throws {
        try await deleteAppointmentPrep(id: prep.id)
    }

    func deleteAppointmentPrep(id: UUID) async throws {
        guard let db = db else { throw DatabaseError.connectionFailed }

        let query = appointmentPrepsTable.filter(prepId == id.uuidString)
        let rowsDeleted = try db.run(query.delete())
        if rowsDeleted == 0 {
            throw DatabaseError.notFound
        }
    }
}
