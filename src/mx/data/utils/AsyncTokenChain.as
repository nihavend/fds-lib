package mx.data.utils
{
   import mx.core.mx_internal;
   import mx.logging.ILogger;
   import mx.logging.Log;
   import mx.rpc.AsyncDispatcher;
   import mx.rpc.AsyncResponder;
   import mx.rpc.AsyncToken;
   import mx.rpc.Fault;
   import mx.rpc.events.FaultEvent;
   import mx.rpc.events.ResultEvent;
   
   public class AsyncTokenChain extends AsyncToken
   {
       
      
      private var pendingInvocations:Array;
      
      private var pendingResults:int = 0;
      
      private var hasFault:Boolean = false;
      
      public function AsyncTokenChain()
      {
         this.pendingInvocations = [];
         super();
      }
      
      public function addPendingAction(token:AsyncToken) : void
      {
         if(token)
         {
            this.pendingResults = this.pendingResults + 1;
            token.addResponder(new AsyncResponder(this.onSubResult,this.onSubFault));
         }
      }
      
      public function addPendingInvocation(requestInvoker:Function, ... args) : void
      {
         var invocation:Object = {
            "func":requestInvoker,
            "args":args
         };
         this.pendingInvocations.push(invocation);
         this.invokeNextRequestOrResult();
      }
      
      public function onSubResult(result:ResultEvent, subToken:AsyncToken = null) : void
      {
         this.pendingResults = this.pendingResults - 1;
         this.invokeNextRequestOrResult();
      }
      
      public function onSubFault(fault:FaultEvent, subToken:AsyncToken = null) : void
      {
         if(!this.hasFault)
         {
            this.hasFault = true;
            this.mx_internal::applyFault(fault);
         }
      }
      
      private function get log() : ILogger
      {
         return Log.getLogger("AsyncTokenChain");
      }
      
      private function invokeNextRequestOrResult() : void
      {
         var invocation:Object = null;
         var requestInvoker:Function = null;
         var args:Array = null;
         var requestToken:AsyncToken = null;
         if(this.pendingResults <= 0 && !this.hasFault)
         {
            if(this.pendingInvocations.length > 0)
            {
               invocation = this.pendingInvocations.shift();
               requestInvoker = invocation.func;
               args = invocation.args;
               try
               {
                  requestToken = requestInvoker.apply(requestInvoker,args);
                  this.addPendingAction(requestToken);
               }
               catch(err:Error)
               {
                  log.error("unexpected exception in token chain: {0}",err.getStackTrace());
                  onSubFault(FaultEvent.createEvent(new Fault("unexpected exception in token chain",err.getStackTrace()),this));
               }
            }
            else
            {
               this.applyFinalResult();
            }
         }
      }
      
      private function applyFinalResult() : void
      {
         this.mx_internal::applyResult(ResultEvent.createEvent(this.result,this));
      }
      
      public function applyFinalResultLater() : void
      {
         new AsyncDispatcher(this.applyFinalResult,[],10);
      }
   }
}
