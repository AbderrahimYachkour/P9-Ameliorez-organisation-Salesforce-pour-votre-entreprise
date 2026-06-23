@isTest
private class OrderTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        Product2 p = TestDataFactory.createProduct('Produit Test');
        TestDataFactory.createStandardPricebookEntry(p.Id, 100);
    }

    private static PricebookEntry getPbe() {
        return [SELECT Id FROM PricebookEntry LIMIT 1];
    }

    @isTest
    static void updateDraftToActivated_updatesAccountCA() {
        Account acc = TestDataFactory.createAccount('Acc Activate');
        Id pbId = Test.getStandardPricebookId();
        PricebookEntry pbe = getPbe();

        Order o = TestDataFactory.createOrder(acc.Id, pbId, TestDataFactory.STATUS_DRAFT);
        TestDataFactory.createOrderItem(o.Id, pbe.Id, 2, 100);

        Test.startTest();
        o.Status = TestDataFactory.STATUS_ACTIVATED;
        update o;
        Test.stopTest();

        Account refreshed = [SELECT Chiffre_d_affaire__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(200, refreshed.Chiffre_d_affaire__c,
            'CA doit etre mis a jour lors de la transition Draft->Activated');
    }

    @isTest
    static void updateActivatedToDraft_recalculatesToZero() {
        Account acc = TestDataFactory.createAccount('Acc Revert');
        Id pbId = Test.getStandardPricebookId();
        PricebookEntry pbe = getPbe();

        Order o = TestDataFactory.createOrder(acc.Id, pbId, TestDataFactory.STATUS_DRAFT);
        TestDataFactory.createOrderItem(o.Id, pbe.Id, 5, 100);
        o.Status = TestDataFactory.STATUS_ACTIVATED;
        update o;

        Test.startTest();
        o.Status = TestDataFactory.STATUS_DRAFT;
        update o;
        Test.stopTest();

        Account refreshed = [SELECT Chiffre_d_affaire__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(0, refreshed.Chiffre_d_affaire__c,
            'CA doit revenir a 0 lors de la transition Activated->Draft');
    }

    @isTest
    static void deleteDraftOrder_doesNotAffectCA() {
        Account acc = TestDataFactory.createAccount('Acc Delete Draft');
        Id pbId = Test.getStandardPricebookId();
        PricebookEntry pbe = getPbe();

        Order activated = TestDataFactory.createOrder(acc.Id, pbId, TestDataFactory.STATUS_DRAFT);
        TestDataFactory.createOrderItem(activated.Id, pbe.Id, 1, 100);
        activated.Status = TestDataFactory.STATUS_ACTIVATED;
        update activated;

        Order draft = TestDataFactory.createOrder(acc.Id, pbId, TestDataFactory.STATUS_DRAFT);
        TestDataFactory.createOrderItem(draft.Id, pbe.Id, 5, 100);

        Test.startTest();
        delete draft;
        Test.stopTest();

        Account refreshed = [SELECT Chiffre_d_affaire__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(100, refreshed.Chiffre_d_affaire__c,
            'CA doit rester a 100 : le delete d\'une Draft ne doit pas declencher de recalcul');
    }

    @isTest
    static void doubleUpdate_noDoubleCounting() {
        Account acc = TestDataFactory.createAccount('Acc Idempotent');
        Id pbId = Test.getStandardPricebookId();
        PricebookEntry pbe = getPbe();

        Order o = TestDataFactory.createOrder(acc.Id, pbId, TestDataFactory.STATUS_DRAFT);
        TestDataFactory.createOrderItem(o.Id, pbe.Id, 1, 100);
        o.Status = TestDataFactory.STATUS_ACTIVATED;
        update o;

        Test.startTest();
        o.Description = 'Modification sans changement de statut';
        update o;
        Test.stopTest();

        Account refreshed = [SELECT Chiffre_d_affaire__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(100, refreshed.Chiffre_d_affaire__c,
            'CA doit rester a 100 : oldMap evite le double comptage');
    }

    @isTest
    static void changeAccountBeforeActivation_updatesCorrectAccount() {
        Account accOld = TestDataFactory.createAccount('Old Acc');
        Account accNew = TestDataFactory.createAccount('New Acc');
        Id pbId = Test.getStandardPricebookId();
        PricebookEntry pbe = getPbe();

        Order o = TestDataFactory.createOrder(accOld.Id, pbId, TestDataFactory.STATUS_DRAFT);
        TestDataFactory.createOrderItem(o.Id, pbe.Id, 1, 100);

        Test.startTest();
        o.AccountId = accNew.Id;
        update o;
        o.Status = TestDataFactory.STATUS_ACTIVATED;
        update o;
        Test.stopTest();

        Map<Id, Account> refreshed = new Map<Id, Account>([
            SELECT Id, Chiffre_d_affaire__c
            FROM Account
            WHERE Id IN :new Set<Id>{ accOld.Id, accNew.Id }
        ]);
        System.assertEquals(null, refreshed.get(accOld.Id).Chiffre_d_affaire__c,
            'Ancien compte ne doit jamais avoir ete recalcule (CA reste null)');
        System.assertEquals(100, refreshed.get(accNew.Id).Chiffre_d_affaire__c,
            'Nouveau compte doit recevoir le CA apres activation');
    }

    @isTest
    static void bulkUpdate_200Orders_noGovernorException() {
        Account acc = TestDataFactory.createAccount('Acc Bulk');
        Id pbId = Test.getStandardPricebookId();
        PricebookEntry pbe = getPbe();

        List<Order> orders = TestDataFactory.createOrders(
            acc.Id, pbId, TestDataFactory.STATUS_DRAFT, 200
        );

        List<Id> orderIds = new List<Id>();
        for (Order o : orders) {
            orderIds.add(o.Id);
        }
        TestDataFactory.createOrderItems(orderIds, pbe.Id, 1, 100);

        for (Order o : orders) {
            o.Status = TestDataFactory.STATUS_ACTIVATED;
        }

        Test.startTest();
        update orders;
        Test.stopTest();

        Account refreshed = [SELECT Chiffre_d_affaire__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(200 * 100, refreshed.Chiffre_d_affaire__c,
            'CA = 20000 pour 200 commandes a 100 chacune (bulk-safe valide)');
    }
}
