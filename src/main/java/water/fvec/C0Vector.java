package water.fvec;

import water.*;

// The empty-compression function, where data is in bytes
public class C0Vector extends BigVector {
  @Override long   at_impl ( int    i ) { return 0xFF&_mem[i]; }
  @Override double atd_impl( int    i ) { throw H2O.unimpl(); }
  @Override void   append2 ( long   l ) { throw H2O.fail(); }
  @Override void   append2 ( double d ) { throw H2O.fail(); }
  @Override public AutoBuffer write(AutoBuffer bb) { return bb.putA1(_mem,_len); }
  @Override public C0Vector read(AutoBuffer bb) { 
    _mem = bb.bufClose(); 
    _start = -1;
    _len = _mem.length;
    return this; 
  }
  public int get2(int off) { return UDP.get2(_mem,off); }
  public int get4(int off) { return UDP.get4(_mem,off); }
}