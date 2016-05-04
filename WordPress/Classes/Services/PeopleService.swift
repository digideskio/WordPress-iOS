import Foundation


/// Service providing access to the People Management WordPress.com API.
///
struct PeopleService {
    typealias Role = Person.Role
    
    let remote: PeopleRemote
    let siteID: Int

    private let context = ContextManager.sharedInstance().mainContext

    
    /// Designated Initializer.
    ///
    /// -   Parameters:
    ///     - blog: Target Blog Instance
    ///
    init(blog: Blog) {
        remote = PeopleRemote(api: blog.restApi())
        siteID = blog.dotComID as Int
    }

    
    /// Refreshes the team of Users associated to a blog.
    ///
    /// -   Parameters:
    ///     - completion: Closure to be executed on completion.
    ///
    func refreshTeam(completion: (Bool) -> Void) {
        remote.getTeamFor(siteID,
            success: { people in

                self.mergeTeam(people)
                completion(true)
            },
            failure: { error in
                DDLogSwift.logError(String(error))
                completion(false)
        })
    }

    /// Updates a given person with the specified role.
    ///
    /// -   Parameters:
    ///     - person: Instance of the person to be updated.
    ///     - role: New role that should be assigned
    ///
    /// -   Returns: A new Person instance, with the new Role already assigned.
    ///
    func updatePerson(person: Person, role: Role) -> Person {
        guard let managedPerson = managedPersonWithID(person.ID) else {
            return person
        }
        
        // OP Reversal
        let reversalRole = managedPerson.role
        let revert = {
            let managedPerson = self.managedPersonWithID(person.ID)
            managedPerson?.role = reversalRole
            ContextManager.sharedInstance().saveContext(self.context)
        }
        
        // Hit the Backend
        remote.updatePersonFor(siteID, personID: person.ID, newRole: role, success: nil, failure: { error in
            
            NSLog("### Error while updating person \(person.ID) in blog \(self.siteID): \(error)")
            revert()
        })
        
        // Pre-emptively update the role
        managedPerson.role = role.description
        ContextManager.sharedInstance().saveContext(context)
        
        return Person(managedPerson: managedPerson)
    }
}


/// Encapsulates all of the PeopleService Private Methods.
///
private extension PeopleService {
    func mergeTeam(people: People) {
        let remotePeople = people
        let localPeople = allPeople()

        let remoteIDs = Set(remotePeople.map({ $0.ID }))
        let localIDs = Set(localPeople.map({ $0.ID }))

        let removedIDs = localIDs.subtract(remoteIDs)
        removeManagedPeopleWithIDs(removedIDs)

        // Let's try to only update objects that have changed
        let remoteChanges = remotePeople.filter {
            return !localPeople.contains($0)
        }
        for remotePerson in remoteChanges {
            if let existingPerson = managedPersonWithID(remotePerson.ID) {
                existingPerson.updateWith(remotePerson)
                DDLogSwift.logDebug("Updated person \(existingPerson)")
            } else {
                createManagedPerson(remotePerson)
            }
        }

        ContextManager.sharedInstance().saveContext(context)
    }

    func allPeople() -> People {
        let request = NSFetchRequest(entityName: "Person")
        request.predicate = NSPredicate(format: "siteID = %@", NSNumber(integer: siteID))
        let results: [ManagedPerson]
        do {
            results = try context.executeFetchRequest(request) as! [ManagedPerson]
        } catch {
            DDLogSwift.logError("Error fetching all people: \(error)")
            results = []
        }

        return results.map { return Person(managedPerson: $0) }
    }

    func managedPersonWithID(id: Int) -> ManagedPerson? {
        let request = NSFetchRequest(entityName: "Person")
        request.predicate = NSPredicate(format: "siteID = %@ AND userID = %@", NSNumber(integer: siteID), NSNumber(integer: id))
        request.fetchLimit = 1
        let results = (try? context.executeFetchRequest(request) as! [ManagedPerson]) ?? []
        return results.first
    }

    func removeManagedPeopleWithIDs(ids: Set<Int>) {
        if ids.isEmpty {
            return
        }

        let numberIDs = ids.map { return NSNumber(integer: $0) }
        let request = NSFetchRequest(entityName: "Person")
        request.predicate = NSPredicate(format: "siteID = %@ AND userID IN %@", NSNumber(integer: siteID), numberIDs)
        let objects = (try? context.executeFetchRequest(request) as! [NSManagedObject]) ?? []
        for object in objects {
            DDLogSwift.logDebug("Removing person: \(object)")
            context.deleteObject(object)
        }
    }

    func createManagedPerson(person: Person) {
        let managedPerson = NSEntityDescription.insertNewObjectForEntityForName("Person", inManagedObjectContext: context) as! ManagedPerson
        managedPerson.updateWith(person)
        DDLogSwift.logDebug("Created person \(managedPerson)")
    }
}
