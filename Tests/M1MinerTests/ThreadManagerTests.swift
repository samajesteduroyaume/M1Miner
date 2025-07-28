import XCTest
@testable import M1MinerCore

class ThreadManagerTests: XCTestCase {
    
    var threadManager: ThreadManager!
    
    override func setUp() {
        super.setUp()
        // Utiliser un nombre limité de threads pour les tests
        threadManager = ThreadManager(maxConcurrentTasks: 2)
    }
    
    override func tearDown() {
        threadManager = nil
        super.tearDown()
    }
    
    // Teste l'exécution d'une tâche simple
    func testExecuteSingleTask() {
        let expectation = self.expectation(description: "Tâche terminée")
        var taskCompleted = false
        
        threadManager.execute(priority: .default) {
            taskCompleted = true
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0) { error in
            if let error = error {
                XCTFail("Attente expirée: \(error)")
            }
            XCTAssertTrue(taskCompleted, "La tâche devrait être terminée")
        }
    }
    
    // Teste l'exécution de plusieurs tâches
    func testExecuteMultipleTasks() {
        let taskCount = 5
        var completedTasks = 0
        let expectation = self.expectation(description: "Toutes les tâches sont terminées")
        
        for i in 0..<taskCount {
            threadManager.execute(priority: .default) {
                // Simuler un travail
                Thread.sleep(forTimeInterval: 0.1)
                
                DispatchQueue.main.async {
                    completedTasks += 1
                    if completedTasks == taskCount {
                        expectation.fulfill()
                    }
                }
            }
        }
        
        waitForExpectations(timeout: 2.0) { error in
            if let error = error {
                XCTFail("Attente expirée: \(error)")
            }
            XCTAssertEqual(completedTasks, taskCount, "Toutes les tâches devraient être terminées")
        }
    }
    
    // Teste la priorité des tâches
    func testTaskPriority() {
        var executionOrder: [Int] = []
        let expectation = self.expectation(description: "Toutes les tâches sont terminées")
        
        // Tâche basse priorité (devrait s'exécuter en dernier)
        threadManager.execute(priority: .low) {
            executionOrder.append(3)
            if executionOrder.count == 3 {
                expectation.fulfill()
            }
        }
        
        // Tâche haute priorité (devrait s'exécuter en premier)
        threadManager.execute(priority: .high) {
            executionOrder.append(1)
            if executionOrder.count == 3 {
                expectation.fulfill()
            }
        }
        
        // Tâche priorité par défaut (devrait s'exécuter en deuxième)
        threadManager.execute(priority: .default) {
            executionOrder.append(2)
            if executionOrder.count == 3 {
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 2.0) { error in
            if let error = error {
                XCTFail("Attente expirée: \(error)")
            }
            
            // Vérifier que les tâches se sont exécutées dans le bon ordre
            XCTAssertEqual(executionOrder, [1, 2, 3], "L'ordre d'exécution devrait respecter les priorités")
        }
    }
    
    // Teste l'exécution synchrone
    func testSyncExecution() {
        var value = 0
        
        threadManager.execute(priority: .default) {
            Thread.sleep(forTimeInterval: 0.5)
            value = 42
        }
        
        // Exécution synchrone
        threadManager.executeSync(priority: .default) {
            value += 1
        }
        
        // Si executeSync fonctionne correctement, cette ligne ne s'exécutera pas avant que la tâche synchrone soit terminée
        XCTAssertEqual(value, 43, "La valeur devrait être mise à jour de manière synchrone")
    }
    
    // Teste l'annulation des tâches
    func testCancelAll() {
        let expectation = self.expectation(description: "Tâche annulée")
        var taskExecuted = false
        
        threadManager.execute(priority: .default) {
            // Cette tâche devrait s'exécuter car elle est déjà en cours
            Thread.sleep(forTimeInterval: 0.5)
            taskExecuted = true
        }
        
        // Annuler toutes les tâches
        threadManager.cancelAll()
        
        // Vérifier après un court délai
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // La tâche en cours devrait se terminer normalement
            XCTAssertTrue(taskExecuted, "La tâche en cours devrait se terminer normalement")
            
            // Vérifier qu'aucune nouvelle tâche n'est acceptée
            var newTaskExecuted = false
            self.threadManager.execute(priority: .default) {
                newTaskExecuted = true
            }
            
            // Attendre un peu pour que la tâche ait le temps de s'exécuter si elle était acceptée
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                XCTAssertFalse(newTaskExecuted, "Aucune nouvelle tâche ne devrait être exécutée après cancelAll()")
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 2.0) { error in
            if let error = error {
                XCTFail("Attente expirée: \(error)")
            }
        }
    }
    
    // Teste les statistiques du gestionnaire de threads
    func testStatistics() {
        let stats = threadManager.getStatistics()
        
        XCTAssertEqual(stats.activeTasks, 0, "Aucune tâche ne devrait être active au démarrage")
        XCTAssertEqual(stats.maxConcurrentTasks, 2, "Le nombre maximum de tâches concurrentes devrait être 2")
        XCTAssertEqual(stats.availableSlots, 2, "Tous les slots devraient être disponibles au démarrage")
        
        let expectation = self.expectation(description: "Tâche en cours")
        
        // Démarrer une tâche qui dure un certain temps
        threadManager.execute(priority: .default) {
            // Laisser le temps de vérifier les statistiques
            Thread.sleep(forTimeInterval: 0.5)
            expectation.fulfill()
        }
        
        // Vérifier les statistiques pendant que la tâche est en cours
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let statsDuring = self.threadManager.getStatistics()
            
            XCTAssertEqual(statsDuring.activeTasks, 1, "Une tâche devrait être en cours d'exécution")
            XCTAssertEqual(statsDuring.availableSlots, 1, "Un seul slot devrait être disponible")
        }
        
        waitForExpectations(timeout: 1.0) { error in
            if let error = error {
                XCTFail("Attente expirée: \(error)")
            }
            
            // Vérifier à nouveau après la fin de la tâche
            let statsAfter = self.threadManager.getStatistics()
            XCTAssertEqual(statsAfter.activeTasks, 0, "Aucune tâche ne devrait être active après la fin")
            XCTAssertEqual(statsAfter.availableSlots, 2, "Tous les slots devraient être disponibles après la fin")
        }
    }
    
    // Teste l'exécution avec délai
    func testDelayedExecution() {
        let expectation = self.expectation(description: "Tâche différée")
        let startTime = Date()
        var endTime: Date?
        
        threadManager.executeAfter(delay: 0.5, priority: .default) {
            endTime = Date()
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0) { error in
            if let error = error {
                XCTFail("Attente expirée: \(error)")
            }
            
            if let endTime = endTime {
                let elapsed = endTime.timeIntervalSince(startTime)
                XCTAssertGreaterThanOrEqual(elapsed, 0.5, "La tâche devrait s'exécuter après le délai spécifié")
                XCTAssertLessThan(elapsed, 0.7, "La tâche ne devrait pas trop tarder après le délai")
            } else {
                XCTFail("La tâche différée ne s'est pas exécutée")
            }
        }
    }
}
