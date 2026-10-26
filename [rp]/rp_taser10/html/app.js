const cid = document.getElementById('cid')
const screenDisplay = document.getElementById('screenDisplay')
const batteryDisplay = document.getElementById('batteryDisplay')
const sounds = {
    arming: new Audio('sound/arming.mp3'),
    switch: new Audio('sound/switch.wav'),
    fire: new Audio('sound/t10fire.wav'),
    connect: new Audio('sound/t10connect.wav'),
    warning: new Audio('sound/warning.mp3')
}
let latestData
let lastArmed = false
let lastFunctionTest = 'inactive'
let animationId = 0
let arming = false

function showScreen(image, size = 'contain') {
    batteryDisplay.classList.add('hidden')
    screenDisplay.style.backgroundImage = `url('${image}')`
    screenDisplay.style.backgroundSize = size
}

function drawCartridges(live, battery) {
    if (Number(battery) <= 0) {
        screenDisplay.style.backgroundImage = "url('imgs/10_depleted_cartiridge.png')"
        screenDisplay.style.backgroundSize = '100% 100%'
        return
    }

    if (live <= 0) {
        screenDisplay.style.backgroundImage = "url('imgs/10_expended_cartiridges.png')"
        screenDisplay.style.backgroundSize = '100% 100%'
        return
    }

    const cartridges = Math.min(10, Math.max(1, Math.round(live)))
    screenDisplay.style.backgroundImage = `url('imgs/charge/cart${cartridges}.png')`
    screenDisplay.style.backgroundSize = '100% 100%'
}

function drawBattery(shotsSpent, display) {
    const spent = Math.max(0, Number(shotsSpent) || 0)
    let image

    if (spent >= display.DepletedThresholdShotsSpent) {
        image = display.DepletedImage
    } else if (spent >= display.LowThresholdShotsSpent) {
        image = display.LowImage
    } else if (spent >= display.HalfThresholdShotsSpent) {
        image = display.HalfImage
    } else {
        image = display.StartImage
    }

    batteryDisplay.classList.remove('hidden')
    batteryDisplay.style.backgroundImage = `url('${image}')`
}

function drawLiveDisplay(data) {
    drawCartridges(data.cartridges, data.battery)
    drawBattery(data.shotsSpent, data.batteryDisplay)
}

function startArmingAnimation() {
    const currentAnimation = ++animationId
    arming = true
    batteryDisplay.classList.add('hidden')

    for (let cartridge = 1; cartridge <= 10; cartridge++) {
        setTimeout(() => {
            if (currentAnimation !== animationId) return
            screenDisplay.style.backgroundImage = `url('imgs/charge/cart${cartridge}.png')`
            screenDisplay.style.backgroundSize = '100% 100%'
        }, (cartridge - 1) * 100)
    }

    setTimeout(() => {
        if (currentAnimation !== animationId) return
        arming = false
        drawLiveDisplay(latestData)
    }, 1000)
}

function startFunctionTest() {
    const currentAnimation = ++animationId
    const frames = ['quarter_load.png', 'half_load.png', 'full_load.png']
    arming = false

    frames.forEach((frame, index) => {
        setTimeout(() => {
            if (currentAnimation !== animationId) return
            showScreen(`imgs/function/${frame}`)
        }, index * 333)
    })

    setTimeout(() => {
        if (currentAnimation !== animationId) return
        showScreen('imgs/function/firmware_1_5_3_red_dock_icon.png')
    }, 1000)
}

window.addEventListener('message', ({ data }) => {
    if (data.action === 'sound') {
        const source = sounds[data.sound]
        if (!source) return

        const sound = source.cloneNode()
        sound.volume = Math.max(0, Math.min(1, Number(data.volume) || 0))
        sound.play().catch(() => {})
        return
    }

    if (data.action !== 'update') return

    const wasArmed = lastArmed
    const functionTestChanged = data.functionTestState !== lastFunctionTest
    latestData = data
    cid.classList.toggle('hidden', !data.visible)
    cid.classList.toggle('stealth', data.stealth)

    if (functionTestChanged) {
        animationId++
        arming = false

        if (data.functionTestState === 'running') {
            startFunctionTest()
        } else if (data.functionTestState === 'passed') {
            showScreen('imgs/function/selector_switch_passed_the_function_test.png')
        } else {
            drawLiveDisplay(data)
        }
    } else if (data.functionTestState === 'inactive') {
        if (data.armed && !wasArmed) {
            startArmingAnimation()
        } else if (!arming) {
            drawLiveDisplay(data)
        }
    }

    lastArmed = data.armed
    lastFunctionTest = data.functionTestState
})
