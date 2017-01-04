# Created by Yinan Shao

# Function
# Convert the MNIST data to a format that can be used in Verilog simulation 

# Need file: mnist.pkl (original MNIST data from http://deeplearning.net/data/mnist/mnist.pkl.gz)
# generate file : train_input.dat, train_result.dat

#### Libraries
# Standard library
import cPickle
import gzip

# Third-party libraries
import numpy as np

def load_data():
    """Return the MNIST data as a tuple containing the training data,
    the validation data, and the test data.
    The ``training_data`` is returned as a tuple with two entries.
    The first entry contains the actual training images.  This is a
    numpy ndarray with 50,000 entries.  Each entry is, in turn, a
    numpy ndarray with 784 values, representing the 28 * 28 = 784
    pixels in a single MNIST image.
    The second entry in the ``training_data`` tuple is a numpy ndarray
    containing 50,000 entries.  Those entries are just the digit
    values (0...9) for the corresponding images contained in the first
    entry of the tuple.
    The ``validation_data`` and ``test_data`` are similar, except
    each contains only 10,000 images.
    This is a nice data format, but for use in neural networks it's
    helpful to modify the format of the ``training_data`` a little.
    That's done in the wrapper function ``load_data_wrapper()``, see
    below.
    """
    f = open("mnist.pkl")
    training_data, validation_data, test_data = cPickle.load(f)
    f.close()
    return (training_data, validation_data, test_data)

def covert_data():
    """create 2 files: train_input.dat and train_result.dat, which store
    the training data. 
    Format for train_input.dat: one sample data (one image) with 784 pixels 
    store in one line seperate by space.

    Format for train_result.dat: one sample data (the mean of one image) 
    store in one line one hot seperate by space.
    For example: 0 0 0 0 0 0 0 0 0 1    reperesent this image is 9
                         0 0 0 1 0 0 0 0 0 0    represent this image is 3
    """
    tr_d, va_d, te_d = load_data()
    training_inputs = [np.reshape(x, (784, 1)) for x in tr_d[0]]
    training_results = [vectorized_result(y) for y in tr_d[1]]
    training_data = zip(training_inputs, training_results)
    validation_inputs = [np.reshape(x, (784, 1)) for x in va_d[0]]
    validation_data = zip(validation_inputs, va_d[1])
    test_inputs = [np.reshape(x, (784, 1)) for x in te_d[0]]
    n = 50000
    for x in range(n):
    	training_inputs[x] = training_inputs[x]*256#np.ones(2, 784)
    train_data = training_inputs[0:n]
    train_result = training_results[0:n]
    # print training_inputs[0:n]
    np.savetxt('train_input.dat', train_data, fmt='%02x', delimiter=' ', newline='\n')
    np.savetxt('train_result.dat', train_result, fmt='%d', delimiter=' ', newline='\n')  
    test_data = zip(test_inputs, te_d[1])
    return (training_data, validation_data, test_data)

def vectorized_result(j):
    """Return a 10-dimensional unit vector with a 1.0 in the jth
    position and zeroes elsewhere.  This is used to convert a digit
    (0...9) into a corresponding desired output from the neural
    network."""
    e = np.zeros((10, 1))
    e[j] = 1.0
    return e


covert_data()
