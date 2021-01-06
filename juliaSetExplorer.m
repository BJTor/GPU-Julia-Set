function figh = juliaSetExplorer(z0)
%juliaSetExplorer  An interface for exploring the Mandelbrot Julia Set
%
%   juliaSetExplorer() launches a simple interface that allows the Julia
%   Set for any location in the Mandelbrot set to be viewed. The location
%   can be varied by clicking or dragging in a small overview window in the
%   top left. Close the window to exit.
%
%   figh = juliaSetExplorer() also returns a handle to the interface window
%   so that it can be captured or close programmatically.

%   Author: Ben Tordoff
%   Copyright 2010-2019 The MathWorks, Inc.

% First make sure we are capable of running this
matlabVersionCheck()
versionStr = '1.3';

% Create the shared data structure
data = struct();
data.WriteVideo = false;
data.DoAnimation = false;
data.LocationList = makeLocationList();
data.NextLocation = 2;
data.MaxIterations = 200;
if nargin>0
    data.z0 = z0;
else
    data.z0 = data.LocationList(1);
end
x = gpuArray.linspace( -2, 2, 800 );
y = gpuArray.linspace( -2, 2, 600 );
[x,y] = meshgrid(x, y);
data.z = complex( x, y );
clear x y;

% Build the interface
gui = createGUI(versionStr);

% Are we capturing video
if data.WriteVideo
    data.VideoWriter = VideoWriter('juliaSetExplorer.avi');
    data.VideoWriter.FrameRate = 20;
    data.VideoWriter.Quality = 90;
    open( data.VideoWriter );
end

% Set the initial view
drawMandelbrot( gui.MandelImage, data.MaxIterations );
onLimitsChanged();

% Animate a set path
if data.DoAnimation
    doAnimation();
end

% Return a handle to the figure if requested
if nargout > 0
    figh = gui.Window;
end


    function gui = createGUI(versionStr)
        gui = struct();
        gui.Window = figure( ...
            'Name', ['Julia Set explorer v', versionStr], ...
            'Renderer', 'ZBuffer', ...
            'NumberTitle', 'off', ...
            'HandleVisibility', 'off', ...
            'MenuBar', 'none', ...
            'ToolBar', 'figure', ...
            'CloseRequestFcn', @onFigureClose );
        
        gui.JuliaAxes = axes( ...
            'Parent', gui.Window, ...
            'Position', [0 0 1 1], ...
            'XLim', [-2 2], 'YLim', [-2 2], ...
            'XTick', [], 'YTick', [], ...
            'DataAspectRatio', [1 1 1] );
        % Add listeners so that we can redraw when the axes are moved
        if isOldGraphics()
            axHandle = handle( gui.JuliaAxes );
            gui.Listeners = [
                handle.listener( axHandle, findprop( axHandle, 'YLim' ), 'PropertyPostSet', @onLimitsChanged )
                ]; %#ok<NBRAK>
        else
            addlistener( gui.JuliaAxes, 'YLim', 'PostSet', @onLimitsChanged );
        end
        
        % Also add a small set of axes for showing the Mandelbrot set
        gui.MandelAxes = axes( ...
            'Parent', gui.Window, ...
            'Position', [0 0.8 0.2 0.2], ...
            'XLim', [-2 0.5], 'YLim', [-1.25 1.25], ...
            'XTick', [], 'YTick', [], ...
            'ButtonDownFcn', @onMandelButtonDown );
        
        gui.JuliaImage = imagesc( 'Parent', gui.JuliaAxes, ...
            'CData', nan, ...
            'XData', [-2 2], 'YData', [-2 2] );
        colormap( gui.JuliaAxes, jet2(1000) );
        colormap( gui.MandelAxes, jet2(1000) );
        % Add a line so that zooming works. Strange but true.
        line( 'Parent', gui.JuliaAxes, ...
            'XData', [-2 2], 'YData', [-2 2], ...
            'Visible', 'off', ...
            'HitTest', 'off' );
        
        
        gui.MandelImage = imagesc( 'Parent', gui.MandelAxes, 'CData', nan, ...
            'XData', [-2 0.5], 'YData', [-1.25 1.25], 'HitTest', 'off' );
        gui.MandelCrosshair = [
            line( 'Parent', gui.MandelAxes, 'XData', [-2 0.5], 'YData', [0 0], 'Color', 'w', ...
            'HitTest', 'off', 'Tag', 'CrossHairH' );
            line( 'Parent', gui.MandelAxes, 'YData', [-1.25 1.25], 'XData', [0 0], 'Color', 'w', ...
            'HitTest', 'off', 'Tag', 'CrossHairV' );
            ];
        
        % Remove some things we don't want from the toolbar and add a
        % toggle to the toolbar to hide the mandelbrot view
        tb = findall( gui.Window, 'Type', 'uitoolbar' );
        delete( findall( tb, 'Tag', 'Standard.FileOpen' ) );
        delete( findall( tb, 'Tag', 'Standard.NewFigure' ) );
        delete( findall( tb, 'Tag', 'Standard.EditPlot' ) );
        delete( findall( tb, 'Tag', 'Exploration.Brushing' ) );
        delete( findall( tb, 'Tag', 'Exploration.DataCursor' ) );
        delete( findall( tb, 'Tag', 'Exploration.Rotate' ) );
        delete( findall( tb, 'Tag', 'DataManager.Linking' ) );
        delete( findall( tb, 'Tag', 'Plottools.PlottoolsOn' ) );
        delete( findall( tb, 'Tag', 'Plottools.PlottoolsOff' ) );
        delete( findall( tb, 'Tag', 'Annotation.InsertLegend' ) );
        delete( findall( tb, 'Tag', 'Annotation.InsertColorbar' ) );
        gui.ShowMandelToggle = uitoggletool( ...
            'Parent', tb, ...
            'CData', readIcon( 'icon_mandel.png' ), ...
            'TooltipString', 'Show/hide the Mandelbrot view', ...
            'State', 'on', ...
            'Separator', 'on', ...
            'ClickedCallback', @onMandelTogglePressed );
        gui.AnimToggle = uitoggletool( ...
            'Parent', tb, ...
            'CData', readIcon( 'icon_play.png' ), ...
            'TooltipString', 'Play an animation', ...
            'State', 'off', ...
            'ClickedCallback', @onAnimTogglePressed );
        % Set the resize function (we can't do this on construction as it
        % would fire!
        set( gui.Window, 'ResizeFcn', @onFigureResize );
    end % createGUI

    function cdata = readIcon( filename )
        [cdata,~,alpha] = imread( filename );
        idx = find( ~alpha );
        page = size(cdata,1)*size(cdata,2);
        cdata = double( cdata ) / 255;
        cdata(idx) = nan;
        cdata(idx+page) = nan;
        cdata(idx+2*page) = nan;
    end % readIcon

    function onMandelButtonDown( ~, ~ )
        pos = get( gui.MandelAxes, 'CurrentPoint' );
        %         fprintf( 'Click at (%f,%f)\n', pos(1,1), pos(1,2) );
        set( gui.Window, ...
            'WindowButtonMotionFcn', @onMandelButtonMotion, ...
            'WindowButtonUpFcn', @onMandelButtonUp );
        updatePosition( complex( pos(1,1), pos(1,2) ) )
    end % onMandelButtonDown

    function onMandelButtonMotion( ~, ~ )
        pos = get( gui.MandelAxes, 'CurrentPoint' );
        updatePosition( complex( pos(1,1), pos(1,2) ) )
    end % onMandelButtonMotion

    function onMandelButtonUp( ~, ~ )
        pos = get( gui.MandelAxes, 'CurrentPoint' );
        set( gui.Window, ...
            'WindowButtonMotionFcn', [], ...
            'WindowButtonUpFcn', [] );
        updatePosition( complex( pos(1,1), pos(1,2) ) )
    end % onMandelButtonUp

    function updatePosition( z0 )
        if ~ishandle( gui.Window )
            return;
        end
        data.z0 = z0;
        drawMandelbrotCrosshair( gui.MandelCrosshair, data.z0 );
        drawJulia( gui.JuliaImage, gui.JuliaAxes, data.z, data.z0, data.DoAnimation, data.MaxIterations );
        % Capture!
        if data.WriteVideo
            currFrame = getframe( gui.Window );
            writeVideo( data.VideoWriter, currFrame );
        else
            drawnow();
        end
    end % updatePosition

    function onLimitsChanged( ~, ~ )
        % To work out what to draw and at what resolution we need the axis
        % limits and pixel counts.
        xlim = get(gui.JuliaAxes,'XLim');
        ylim = get(gui.JuliaAxes,'YLim');
        pixpos = getpixelposition( gui.JuliaAxes );
        x = gpuArray.linspace( xlim(1), xlim(2), max(0,round(pixpos(3))) );
        y = gpuArray.linspace( ylim(1), ylim(2), max(0,round(pixpos(4))) );
        [x,y] = meshgrid(x, y);
        data.z = complex( x, y );
        set( gui.JuliaImage, 'XData', xlim, 'YData', ylim );
        % Use "update position to force a redraw"
        updatePosition( data.z0 );
    end % onLimitsChanged

    function onFigureClose( ~, ~ )
        % Clear up
        if data.WriteVideo
            close( data.VideoWriter );
        end
        delete( gui.Window );
    end % onFigureClose

    function onFigureResize( ~, ~ )
        pos = getpixelposition( gui.JuliaAxes );
        aspect = pos(4)/pos(3);
        
        % Make sure the Mandelbrot preview is square and not too big
        mandelX = min( 0.2, 200/pos(3) );
        mandelY = mandelX/aspect;
        set( gui.MandelAxes, 'Position', [0 0 mandelX mandelY] );
        
        % Set the Julia-set axes to exactly fill the figure and the
        % resolution to match the axes size
        pos = get( gui.Window, 'Position' );
        xlim = get( gui.JuliaAxes, 'XLim' );
        ylim = get( gui.JuliaAxes, 'YLim' );
        delta_ylim = ( diff( xlim )*pos(4)/pos(3) - diff( ylim ) ) / 2;
        data.WindowPixelSize = pos(3:4);
        % Set the YLim to give the correct aspect. This will trigger a
        % redraw
        set( gui.JuliaAxes, 'YLim', ylim + delta_ylim*[-1 1] );
    end % onFigureResize

    function onMandelTogglePressed( ~, ~ )
        % Toggle the Mandelbrot view on and off
        state = get( gui.ShowMandelToggle, 'State' );
        set( gui.MandelAxes, 'Visible', state, 'HitTest', state );
        set( gui.MandelImage, 'Visible', state );
        set( gui.MandelCrosshair, 'Visible', state );
    end

    function onAnimTogglePressed( ~, ~ )
        % Toggle the Mandelbrot view on and off
        data.DoAnimation = strcmpi( get( gui.AnimToggle, 'State' ), 'on' );
        if data.DoAnimation
            doAnimation();
        end
    end

    function doAnimation()
        while data.DoAnimation
            if ~ishandle( gui.Window )
                return;
            end
            updatePosition( data.LocationList(data.NextLocation) );
            data.NextLocation = mod( data.NextLocation, numel( data.LocationList ) ) + 1;
        end
        % Do a final redraw with animation off
        updatePosition( data.LocationList(data.NextLocation) );
    end  % doAnimation

end


function drawMandelbrot( imh, maxIters )
escapeRadius2 = 400; % Square of escape radius
x = gpuArray.linspace( -2, 0.5, 500 );
y = gpuArray.linspace( -1.2, 1.2, 500 );
[x0,y0] = meshgrid(x, y);

logCount = arrayfun( @processMandelbrotElement, x0, y0, escapeRadius2, maxIters );

set( imh, ...
    'CData', gather(logCount), ...
    'XData', [-2 0.5], 'YData', [-1.2 1.2] );
set( ancestor( imh, 'axes' ), 'XLim', [-2 0.5], 'YLim', [-1.2 1.2] );
end % drawMandelbrot


function drawMandelbrotCrosshair( l, z0 )
hline = l(1);
vline = l(2);

set( vline, 'XData', real(z0)*[1 1] );
set( hline, 'YData', imag(z0)*[1 1] );

end % drawMandelbrotCrosshair

function drawJulia( imh, axh, z, z0, animating, maxIterations )
escapeRadius2 = 100; % Square of escape radius

if animating && numel(z)>1e6
    z = z(1:2:end,1:2:end);
end

logCount = arrayfun( @processJuliaSetElement, z, z0, escapeRadius2, maxIterations );

set( imh, 'CData', gather( logCount ) );
set( axh, 'CLim', [1 log(maxIterations)] );

end % drawJulia

function [logCount,t] = processMandelbrotElement( x0, y0, escapeRadius2, maxIterations )
% Evaluate the Mandelbrot function for a single element
t = 1;
z0 = complex( x0, y0 );
z = z0;
count = 0;
while count <= maxIterations && (z*conj(z) <= escapeRadius2)
    z = z*z + z0;
    count = count + 1;
end
magZ2 = max(real(z).^2 + imag(z).^2,escapeRadius2);
logCount = log( count + 1 - log( log( magZ2 ) / 2 ) / log(2) );
end % processMandelbrotElement

function logCount = processJuliaSetElement( z, z0, escapeRadius2, maxIterations )
% Evaluate the Julia set function for a single element

count = 0;
magZ2 = real(z)^2 + imag(z)^2;
while count <= maxIterations && (magZ2 <= escapeRadius2)
    z = z*z + z0;
    count = count + 1;
    magZ2 = real(z)^2 + imag(z)^2;
end
% Iterate twice more to help smoothing
z = z.*z + z0;  z = z.*z + z0;  count = count + 2;
% Now adjust the count using the magnitude to get smoothing
magZ2 = max( real(z)^2 + imag(z)^2, escapeRadius2 );
logCount = log( count + 2 - log( log( magZ2 ) / 2 ) / log(2) );
end % processJuliaSetElement

function matlabVersionCheck()
% R2011b is v7.13
majorMinor = sscanf( version, '%d.%d' );
if (majorMinor(1)<7) || (majorMinor(1)==7 && majorMinor(2)<13)
    error( 'mandelbrotViewer:MATLABTooOld', 'mandelbrotViewer requires MATLAB R2011b or above.' );
end
end % matlabVersionCheck

function cmap = jet2(m)
% Jet colormap with added fade to black

% A list of break-point colors
colors = [
    0.0  0.0  0.5
    0.0  0.0  1.0
    0.0  0.5  1.0
    0.0  1.0  1.0
    0.5  1.0  0.5
    1.0  1.0  0.0
    1.0  0.5  0.0
    1.0  0.0  0.0
    0.5  0.0  0.0
    0.5  0.0  0.0
    1.0  0.0  0.0
    1.0  0.5  0.0
    1.0  1.0  0.0
    0.5  1.0  0.5
    0.0  1.0  1.0
    0.0  0.5  1.0
    0.0  0.0  1.0
    0.0  0.0  0.5
    0.0  0.0  0.0
    ];

% Now work out the indices into the map
N = size( colors, 1 );
idxIn = 1:N;
idxOut = linspace( 1, N, m );
cmap = [
    interp1( idxIn, colors(:,1), idxOut )
    interp1( idxIn, colors(:,2), idxOut )
    interp1( idxIn, colors(:,3), idxOut )
    ]';
end % jet2


function locations = makeLocationList()
breakpoints = [
    0.29
    0.47 + 0.157143i
    0.4442 + 0.3286i
    0.354911 + 0.585714i
    0.2103 + 0.5551i
    -0.0827 + 0.8355i
    -0.158482 + 1.042857i
    -0.5826 + 0.6143i
    -0.7533 + 0.1178i
    -1.008216 + 0.35i
    -1.25 + 0.2i
    -1.25
    0.29
    ];
numSteps = 10000;
N = numel(breakpoints);
re = interp1( 1:N, real( breakpoints ), linspace( 1, N, numSteps ) );
im = interp1( 1:N, imag( breakpoints ), linspace( 1, N, numSteps ) );
locations = complex( re, im );
end

function out = isOldGraphics()
%ISOLDGRAPHICS Determine whether we are using MATLABs old graphics system
try
    out = verLessThan('matlab','8.4.0');
catch err %#ok<NASGU>
    % If we couldn't even call the test, assume old graphics
    out = true;
end

end