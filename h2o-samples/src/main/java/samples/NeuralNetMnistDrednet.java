package samples;

import hex.*;
import hex.Layer.VecSoftmax;
import hex.Layer.VecsInput;
import water.fvec.Vec;

/**
 * Same as previous MNIST sample but using Rectifier units and Dropout.
 */
public class NeuralNetMnistDrednet extends NeuralNetMnist {
  public static void main(String[] args) throws Exception {
    Class job = Class.forName(Thread.currentThread().getStackTrace()[1].getClassName());
    samples.launchers.CloudLocal.launch(job, 1);
    //samples.launchers.CloudRemote.launchIPs(job, "192.168.1.161", "192.168.1.162", "192.168.1.163", "192.168.1.164");
    //samples.launchers.CloudRemote.launchEC2(job, 8);
  }

  @Override protected Layer[] build(Vec[] data, Vec labels, VecsInput inputStats, VecSoftmax outputStats) {
    Layer[] ls = new Layer[5];
    ls[0] = new VecsInput(data, inputStats);
    ls[1] = new Layer.RectifierDropout(1024);
    ls[2] = new Layer.RectifierDropout(1024);
    ls[3] = new Layer.RectifierDropout(2048);
    ls[4] = new VecSoftmax(labels, outputStats);
    for( int i = 0; i < ls.length; i++ ) {
      ls[i].rate = .01f;
      ls[i].rate_annealing = 1e-6f;
      ls[i].momentum_start = .5f;
      ls[i].momentum_ramp = 60000 * 30;
      ls[i].momentum_stable = .99f;
      ls[i].l1 = .00001f;
      ls[i].init(ls, i);
    }
    return ls;
  }

  @Override protected void startTraining(Layer[] ls) {
    // Initial training on one thread to increase stability
    // If the net still produces NaNs, reduce learning rate
    System.out.println("Initial single-threaded training");
    _trainer = new Trainer.Direct(ls, .1, self());
    _trainer.start();
    _trainer.join();

    System.out.println("Main training");
    _trainer = new Trainer.MapReduce(ls, 0, self());
    _trainer.start();
  }
}
