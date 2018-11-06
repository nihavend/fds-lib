package mx.data
{
   public final class PageInformation
   {
       
      
      private var _loadedPages:Object;
      
      private var _pageCount:int;
      
      private var _pageSize:int;
      
      public function PageInformation(pageSize:int, pageCount:int, loadedPages:Object)
      {
         super();
         this._pageSize = pageSize;
         this._pageCount = pageCount;
         this._loadedPages = loadedPages;
      }
      
      public function get loadedPages() : Object
      {
         return this._loadedPages;
      }
      
      public function get pageSize() : int
      {
         return this._pageSize;
      }
      
      public function get pageCount() : int
      {
         return this._pageCount;
      }
   }
}
