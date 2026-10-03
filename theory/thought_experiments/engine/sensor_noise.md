# Noise in an image sensor

## The model

In the linear model of the [EMVA 1288](#src:EMVA-1288) standard, a pixel's mean reading in digital numbers is a dark offset plus a gain $K$ times the mean number of electrons the pixel collects. Four sources make a reading depart from that mean, and [Janesick](#src:Janesick-2007) treats each in full:

1. **Shot noise.** Photons arrive as a Poisson process, and the number of electrons collected has variance equal to its mean, $\mu_e$.
2. **Read noise.** The readout electronics and the dark current add a temporal variance $\sigma_d^2$, present with no light at all.
3. **Quantization noise.** Rounding to an integer number adds a variance of $1/12$ in squared digital numbers, when the rounding error is uniform over one step.
4. **Fixed-pattern noise.** The offset and the gain differ from pixel to pixel, the dark signal and photo-response nonuniformities, and the difference is the same in every frame.

The first three change from frame to frame and the fourth does not. The temporal variance of one pixel is

$$\sigma_y^2 = K^2\left(\sigma_d^2 + \mu_e\right) + \frac{1}{12}.$$

The sources are independent, and it is their variances that add. Adding their magnitudes overstates the noise of a frame, and summing those magnitudes over $n$ frames overstates the noise of the stack.

## Separating the sources

Two measurements separate the four without any model of the sensor's physics.

**The photon transfer curve.** The temporal variance plotted against the mean signal above dark is a straight line. Its slope is the gain $K$, and its intercept is $K^2\sigma_d^2 + 1/12$, the read and quantization noise together, as [Janesick](#src:Janesick-2007) sets out.

**Averaging frames.** The mean of $n$ frames of a static scene has variance

$$\operatorname{Var}\left(\bar{y}_n\right) = \frac{\sigma_y^2}{n} + \sigma_{\mathrm{fp}}^2,$$

where $\sigma_{\mathrm{fp}}^2$ is the fixed pattern's variance across pixels. Plotted against $1/n$, the slope is the temporal variance and the intercept is the fixed pattern. Averaging more frames removes the temporal sources and leaves the fixed pattern, which only a map of each pixel removes.

## What the model does not claim

The model treats the four sources as random variables, and its tests decide only the statistics they predict. An account in which every photon arrival is fixed by an initial state would make each frame's noise a function of that state. It predicts no statistic that differs from these, and no measurement of a sensor separates it from the model.

## Status

The engine's simulations generate readings by the same law, an offset plus a fixed pattern plus a gain times the signal plus read noise, in exact integers. On a simulated sensor they find a planted fixed pattern and remove it exactly, as the [engine workbook](#src:Quigg-engine-workbook) records. The photon transfer curve and the frame-averaging intercept are measurements of a physical sensor, and neither is run here.
