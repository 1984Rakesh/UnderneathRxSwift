//: **Underneath RxSwift**
//: * This play ground only tries to understand, How problems related to async programming lead to creation of reactive programing

import Foundation

//: * Class Cat that holds information related to how cute a cat is
class Cat : Comparable, CustomDebugStringConvertible {
    var cuteness : Int = 0
    
    init(_ cuteness:Int) {
        self.cuteness = cuteness
    }
    
    var debugDescription: String {
        return "Cutness :: \(cuteness)"
    }
    
    static func < (lhs: Cat, rhs: Cat) -> Bool {
        return lhs.cuteness < rhs.cuteness
    }
    
    static func == (lhs: Cat, rhs: Cat) -> Bool {
        return lhs.cuteness == rhs.cuteness
    }
}

//: Few cats
var cats = [Cat(1),Cat(3),Cat(4),Cat(6),Cat(7),Cat(1),Cat(10),Cat(11)]

//: Asimple sync Network interface to get cats and to save cats
protocol NetworkInterface {
    func getCats(_ query:String) -> [Cat]
    func putCat(_ cat:Cat) -> Cat
}

//: * A view model that finds the cutest cats and saves the cutest one
//: * Alls good, the things considered below are synchronous hence everything looks simple, and there is no error progation if any.
class CatViewModel {
    var api : NetworkInterface?
    
    func saveTheCutestCat(query:String) -> Cat? {
        if let cats = api?.getCats(query),
           let cutestCat = findCutest(cats: cats){
            return api?.putCat(cutestCat)
        }
        return nil
    }
    
    func findCutest(cats:[Cat]) -> Cat? {
        cats.sorted(by: > ).first
    }
}

//: * Lets make the Network Interface Async, now we have introduced a call back and a return value Result.
//: * A callback which will be called to let us know that the async operation is done along with the result of the operation.
//: * Result will either be the success and hold a value or a failure with error.
class NetworkError : LocalizedError {
}

class AsyncNetworkInterface {
    func getCats(_ query:String, callBack:@escaping (Result<[Cat],NetworkError>) -> Void) {
        let queue = DispatchQueue.global(qos: .userInteractive)
        queue.async {
            callBack(.success(cats))
        }
    }
    
    func putCat(_ cat:Cat, callBack:@escaping (Result<Cat,NetworkError>) -> Void) {
        cats.append(cat)
        let queue = DispatchQueue.global(qos: .userInteractive)
        queue.async {
            callBack(.success(cat))
        }
    }
}

//: * Nesting this Async operations causes the callback to be nestes as well.
//: * Just look at those callbacks within callbacks, that nesting is sure hard to understand and debug
//: * If we seprate the callback from function call it will remove the nesting but will cause us to ead the programming from bottom up.
class AsyncCatsViewModel {
    let api = AsyncNetworkInterface()
    
    func saveTheCutestCat(query:String,callBack:@escaping (Result<Cat,NetworkError>)->Void){
        api.getCats(query) { result in
            switch result {
            case .success(let _cats):
                self.findCutest(cats: _cats) { result2 in
                    switch result2 {
                    case .success(let _cat):
                        self.api.putCat(_cat,callBack:callBack)
                        
                    case .failure(let error):
                        callBack(.failure(error))
                    }
                }
                
            case .failure(let error):
                callBack(.failure(error))
            }
        }
    }
    
    func findCutest(cats:[Cat], callBack:@escaping (Result<Cat,NetworkError>)->Void) {
        let queue = DispatchQueue.global(qos: .userInteractive)
        queue.async {
            if let cat = cats.sorted(by: > ).first {
                callBack(.success(cat))
            }
            
            else {
                callBack(.failure(NetworkError()))
            }
        }
    }
}

//: If we look in the above exapmle. every function have a few parameters and a callback.
//: So every function has a callback.
//: lets separate the callback part from the arguement part.
//: instead of have callback as argument lets return an object, which will start the asyn job and will have a callback
class AsyncJob<A> {
    typealias Job = ( @escaping (Result<A,NetworkError>)->Void )->Void
    var job : Job
    
    private init( job:@escaping Job ){
        self.job = job
    }
    
    static func create(_ job:@escaping Job ) -> AsyncJob<A>{
        AsyncJob(job: job)
    }
    
    func start(callBack:@escaping (Result<A,NetworkError>)->Void) {
        job(callBack)
    }
}

//: So now each function returns an Async Job that can be executed later with a callback
class AsyncJobsNetworkInterface {
    func getCats(_ query:String ) -> AsyncJob<[Cat]> {
        return AsyncJob.create { (callBack) in
            let queue = DispatchQueue.global(qos: .userInteractive)
            queue.async {
                print("Got Cats :: \(cats)")
                callBack(.success(cats))
            }
        }
    }
    
    func putCat(_ cat:Cat) -> AsyncJob<Cat> {
        return AsyncJob.create { (callBack) in
            cats.append(cat)
            let queue = DispatchQueue.global(qos: .userInteractive)
            queue.async {
                print("Put Cat :: \(cat)")
                callBack(.success(cat))
            }
        }
    }
}

//: LOL introducing the async job has made the code worse.
//: It has actually increased the code complexity and reduced readability
class AsyncJobCatsViewModel {
    let api = AsyncJobsNetworkInterface()
    
    func saveTheCutestCat(query:String,callBack:@escaping (Result<Cat,NetworkError>)->Void){
        let getCatsJob = api.getCats(query)
        getCatsJob.start { (result) in
             switch result {
             case .success(let cats):
                 let cutestCatJob = self.findCutest(cats: cats)
                 cutestCatJob.start() { (result2) in
                     switch result2 {
                     case .success(let cat):
                         let saveCutestCatJob = self.api.putCat(cat)
                         saveCutestCatJob.start { (result3) in
                             switch result3 {
                             case .failure(let error):
                                 callBack(.failure(error))
                                 
                             case .success(let cat):
                                 callBack(.success(cat))
                             }
                         }
                         
                     case .failure(let error):
                         callBack(.failure(error))
                     }
                 }
                 
             case .failure(let error):
                 callBack(Result.failure(error))
             }
         }
    }
    
    func findCutest(cats:[Cat]) -> AsyncJob<Cat> {
        return AsyncJob.create { (callBack) in
            let queue = DispatchQueue.global(qos: .userInteractive)
            queue.async {
                if let cat = cats.sorted(by:>).first {
                    callBack(.success(cat))
                }
                
                else {
                    callBack(.failure(NetworkError()))
                }
            }
        }
    }
}

/*:
 * but if we look closely, switch statements are repetative
    * every job has result with success/failure
    * failure causes to return with error
    * success invokes next job with value from the previous job, meaning on success value is passed from one Job to another
 * In order to remove this dupplication lets having a mapping from one job to another
 */
extension AsyncJob {
    func map<B>( _ function:@escaping (A) -> AsyncJob<B>  ) -> AsyncJob<B> {
        return AsyncJob<B> { (callBack) in
            self.start { (result) in
                switch result {
                case .success(let a):
                    function(a).start(callBack: callBack)
                    
                case .failure(let e):
                    callBack(.failure(e))
                }
            }
        }
    }
}

//: * And here we are simply passing value from one job to another with much readable code and few line as well since we have now taken care of duplicate code
extension AsyncJobCatsViewModel {
    func saveTheCutestCatWithMap(query:String,callBack:@escaping (Result<Cat,NetworkError>)->Void){
        let saveCutestCatJsob = api.getCats(query)
            .map( { self.findCutest(cats: $0) } )
            .map( { self.api.putCat($0) } )
        
        saveCutestCatJsob.start(callBack: callBack)
    }
}

let viewModel = AsyncJobCatsViewModel()
viewModel.saveTheCutestCat(query: "") { (result) in
    switch result {
    case .success(let cat):
        print(cat)
        
    case .failure(let e):
        print(e)
    }
}

