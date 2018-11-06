package mx.data
{
   [ExcludeClass]
   public class RemoveFromFillConflictDetails
   {
       
      
      private var _acceptServerCallBackFunction:Function;
      
      private var _acceptServerCallBackArgs:Array;
      
      private var _acceptServerCallBackThis;
      
      public function RemoveFromFillConflictDetails(acceptServerCallBackFunction:Function, acceptServerCallBackArgs:Array, acceptServerCallBackThis:*)
      {
         super();
         this._acceptServerCallBackFunction = acceptServerCallBackFunction;
         this._acceptServerCallBackArgs = acceptServerCallBackArgs;
         this._acceptServerCallBackThis = acceptServerCallBackThis;
      }
      
      public function get acceptServerCallBackFunction() : Function
      {
         return this._acceptServerCallBackFunction;
      }
      
      public function get acceptServerCallBackArgs() : Array
      {
         return this._acceptServerCallBackArgs;
      }
      
      public function get acceptServerCallBackThis() : *
      {
         return this._acceptServerCallBackThis;
      }
      
      public function applyServerCallBack() : void
      {
         this._acceptServerCallBackFunction.apply(this._acceptServerCallBackThis,this._acceptServerCallBackArgs);
      }
   }
}
