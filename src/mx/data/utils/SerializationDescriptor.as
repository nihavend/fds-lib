package mx.data.utils
{
   [ExcludeClass]
   public dynamic class SerializationDescriptor
   {
       
      
      private var _excludes:Array;
      
      private var _includes:Array;
      
      public function SerializationDescriptor()
      {
         super();
      }
      
      public function setExcludes(excludes:Array) : void
      {
         this._excludes = excludes;
      }
      
      public function getExcludes() : Array
      {
         return this._excludes;
      }
      
      public function setIncludes(includes:Array) : void
      {
         this._includes = includes;
      }
      
      public function getIncludes() : Array
      {
         return this._includes;
      }
   }
}
