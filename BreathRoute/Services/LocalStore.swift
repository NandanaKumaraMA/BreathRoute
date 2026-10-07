import CoreData
import Foundation

/// A small Core Data repository. Payloads are versioned Codable records, indexed by UUID/kind.
/// An explicit model avoids requiring generated NSManagedObject subclasses.
@MainActor
final class LocalStore {
    private let container: NSPersistentContainer
    init(inMemory: Bool = false) throws {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "Record"
        entity.managedObjectClassName = "NSManagedObject"
        func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
            let a = NSAttributeDescription(); a.name = name; a.attributeType = type; return a
        }
        entity.properties = [attribute("id", .UUIDAttributeType), attribute("kind", .stringAttributeType), attribute("payload", .binaryDataAttributeType)]
        entity.uniquenessConstraints = [["id"]]
        model.entities = [entity]
        container = NSPersistentContainer(name: "BreatheRouteV1", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
        if !inMemory {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            description.url = folder.appendingPathComponent("BreatheRouteV1.sqlite")
        }
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
    }
    func read<T: Decodable>(_ kind: String, as type: T.Type) throws -> [T] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Record")
        request.predicate = NSPredicate(format: "kind == %@", kind)
        return try container.viewContext.fetch(request).map { record in
            guard let data = record.value(forKey: "payload") as? Data else { throw CocoaError(.coderReadCorrupt) }
            return try JSONDecoder().decode(type, from: data)
        }
    }
    func save<T: Encodable>(_ item: T, id: UUID, kind: String) throws {
        let context = container.viewContext
        do {
            let data = try JSONEncoder().encode(item)
            let request = NSFetchRequest<NSManagedObject>(entityName: "Record")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let record = try context.fetch(request).first ?? NSEntityDescription.insertNewObject(forEntityName: "Record", into: context)
            record.setValue(id, forKey: "id"); record.setValue(kind, forKey: "kind"); record.setValue(data, forKey: "payload")
            try context.save()
        } catch { context.rollback(); throw error }
    }
    func delete(id: UUID) throws {
        let context = container.viewContext
        do {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Record")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            try context.fetch(request).forEach(context.delete)
            try context.save()
        } catch { context.rollback(); throw error }
    }
}
